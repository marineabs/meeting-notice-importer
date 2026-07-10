import Foundation

struct AIMeetingPayload: Decodable {
    let title: String?
    let date: String?
    let startTime: String?
    let endTime: String?
    let location: String?
    let meetingURL: String?
    let attendees: String?
    let warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case title, date, location, attendees, warnings
        case startTime = "start_time"
        case endTime = "end_time"
        case meetingURL = "meeting_url"
    }
}

struct MeetingAIResultMapper {
    func map(
        _ payload: AIMeetingPayload,
        originalText: String,
        referenceDate: Date,
        method: ParsingMethod
    ) -> ParsingResult {
        let local = MeetingTextParser().parse(originalText, referenceDate: referenceDate)
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "zh_CN")

        let aiDate = parseDate(payload.date, calendar: calendar)
        let baseDate = aiDate ?? local.draft.startDate
        let aiStartTime = parseTime(payload.startTime)
        let localStart = calendar.dateComponents([.hour, .minute], from: local.draft.startDate)
        let startTime = aiStartTime ?? (hour: localStart.hour ?? 9, minute: localStart.minute ?? 0)
        let startDate = calendar.date(
            bySettingHour: startTime.hour,
            minute: startTime.minute,
            second: 0,
            of: baseDate
        ) ?? local.draft.startDate

        var warnings = payload.warnings ?? []
        let endDate: Date
        if let aiEndTime = parseTime(payload.endTime) {
            var candidate = calendar.date(
                bySettingHour: aiEndTime.hour,
                minute: aiEndTime.minute,
                second: 0,
                of: baseDate
            ) ?? startDate.addingTimeInterval(3_600)
            if candidate <= startDate {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                warnings.append("结束时间早于开始时间，已按跨天会议处理，请确认。")
            }
            endDate = candidate
        } else {
            endDate = startDate.addingTimeInterval(3_600)
        }

        if aiDate == nil, nonBlank(payload.date) != nil {
            warnings.append("AI 返回的日期格式无效，已使用本地识别结果。")
        }
        if aiDate == nil {
            warnings.append(contentsOf: local.draft.warnings.filter { $0.contains("日期") })
        }

        let title = nonBlank(payload.title) ?? local.draft.title
        let location = nonBlank(payload.location) ?? local.draft.location
        let meetingURL = validURLString(payload.meetingURL) ?? local.draft.meetingURL
        let attendees = nonBlank(payload.attendees) ?? local.draft.attendees

        var fields: Set<RecognizedField> = [.title, .startTime, .endTime]
        if aiDate != nil || local.recognizedFields.contains(.date) { fields.insert(.date) }
        if !location.isEmpty { fields.insert(.location) }
        if !meetingURL.isEmpty { fields.insert(.meetingURL) }
        if !attendees.isEmpty { fields.insert(.attendees) }

        let draft = MeetingDraft(
            title: title,
            originalText: originalText.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: endDate,
            location: location,
            meetingURL: meetingURL,
            attendees: attendees,
            reminderMinutes: 15,
            warnings: Array(Set(warnings)).sorted()
        )
        return ParsingResult(draft: draft, recognizedFields: fields, method: method)
    }

    private func parseDate(_ value: String?, calendar: Calendar) -> Date? {
        guard let value = nonBlank(value) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private func parseTime(_ value: String?) -> (hour: Int, minute: Int)? {
        guard let value = nonBlank(value) else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func validURLString(_ value: String?) -> String? {
        guard let value = nonBlank(value), let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return value
    }
}

enum MeetingAIPrompt {
    static func system(referenceDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd EEEE HH:mm"

        return """
        你是会议通知结构化提取器。只返回一个合法 JSON 对象，不要 Markdown，不要解释。
        当前系统时间：\(formatter.string(from: referenceDate))，时区：\(TimeZone.current.identifier)。

        JSON 字段必须完整：
        {
          "title": "凝练后的会议名称",
          "date": "yyyy-MM-dd 或 null",
          "start_time": "HH:mm 或 null",
          "end_time": "HH:mm 或 null",
          "location": "地点或空字符串",
          "meeting_url": "线上会议链接或空字符串",
          "attendees": "参会人员，使用顿号分隔，或空字符串",
          "warnings": ["需要用户确认的歧义"]
        }

        提取规则：
        1. title 必须概括实际会议主题或会议类型；去掉日期、时段、问候语和“通知”等包装。多个并列会议应合并，例如“局务会、党组会”。不得输出“未命名会议”。
        2. 通知未写年份时使用系统当前年份。相对日期结合当前系统时间换算，并在 warnings 说明原始相对表达。
        3. 有明确开始时间则原样换算为24小时制；仅写上午默认09:00，下午默认14:00，晚上或晚间默认18:30；完全没有时段默认09:00。
        4. 缺少结束时间时输出 null，由客户端补一小时。不得臆造地点、链接或参会人员。
        5. 从“在某会议室召开”等自然语句提取地点，从“请某某参加”等语句提取参会人员。
        """
    }

    static func user(text: String) -> String {
        "请将下面的会议通知提取为 JSON：\n\n\(text)"
    }
}

enum AIResponseContentDecoder {
    static func jsonData(from content: String) -> Data? {
        var value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```"), let firstLineEnd = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: firstLineEnd)...])
            if let closingRange = value.range(of: "```", options: .backwards) {
                value = String(value[..<closingRange.lowerBound])
            }
        }
        return value.data(using: .utf8)
    }
}
