import Foundation

struct MeetingTextParser {
    private let calendar: Calendar
    private let defaultDuration: TimeInterval

    init(calendar: Calendar = .current, defaultDurationMinutes: Int = 60) {
        var localizedCalendar = calendar
        localizedCalendar.locale = Locale(identifier: "zh_CN")
        self.calendar = localizedCalendar
        self.defaultDuration = TimeInterval(defaultDurationMinutes * 60)
    }

    func parse(_ rawText: String, referenceDate: Date = Date()) -> ParsingResult {
        let text = normalize(rawText)
        var recognized = Set<RecognizedField>()
        var warnings: [String] = []

        let title = extractTitle(from: text)
        recognized.insert(.title)

        let dateResult = extractDate(from: text, referenceDate: referenceDate)
        if dateResult.wasRecognized { recognized.insert(.date) }
        if let warning = dateResult.warning { warnings.append(warning) }

        let timeResult = extractTimes(from: text)
        if timeResult.start != nil { recognized.insert(.startTime) }
        if timeResult.end != nil { recognized.insert(.endTime) }

        let baseDate = dateResult.date ?? referenceDate
        let periodDefault = defaultStartTime(from: text)
        let startComponents = timeResult.start ?? periodDefault?.time ?? (hour: 9, minute: 0)
        let startDate = date(bySetting: startComponents, on: baseDate)
        let endDate: Date

        if let endComponents = timeResult.end {
            var candidate = date(bySetting: endComponents, on: baseDate)
            if candidate <= startDate {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                warnings.append("结束时间早于开始时间，已按跨天会议处理，请确认。")
            }
            endDate = candidate
        } else {
            endDate = startDate.addingTimeInterval(defaultDuration)
        }

        if !dateResult.wasRecognized {
            warnings.append("未识别到会议日期，暂按今天填写，请务必确认。")
        }
        let location = extractLabeledValue(
            from: text,
            labels: ["会议地点", "地点", "地址"],
            stoppingAt: ["时间", "日期", "参会", "联系人", "会议链接", "链接"]
        )
        if !location.isEmpty { recognized.insert(.location) }

        let attendees = extractAttendees(from: text)
        if !attendees.isEmpty { recognized.insert(.attendees) }

        let meetingURL = extractURL(from: text)
        if !meetingURL.isEmpty { recognized.insert(.meetingURL) }

        let draft = MeetingDraft(
            title: title,
            originalText: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: endDate,
            location: location,
            meetingURL: meetingURL,
            attendees: attendees,
            reminderMinutes: 15,
            warnings: warnings
        )
        return ParsingResult(draft: draft, recognizedFields: recognized, method: .localRules)
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTitle(from text: String) -> String {
        let labeledPatterns = [
            #"(?im)^\s*(?:会议主题|研究主题|会议名称|主要会议内容|主要内容|会议内容|研究内容|主题|议题)\s*:\s*([^\n]+)"#,
            #"(?im)^\s*关于(?:召开|举行|开展)?\s*(.+?)(?:的通知|通知)\s*$"#
        ]
        for pattern in labeledPatterns {
            if let value = firstCapture(pattern, in: text) {
                return condensedTitle(from: value)
            }
        }

        let topicBeforeActionPattern = #"(?im)(?:关于|围绕|就)\s*([^，。；;\n]{2,32}?)(?:进行|开展|组织)?\s*(研究|讨论|审议|评审|汇报|部署|推进|协调|沟通|交流|培训|复盘)"#
        if let captures = firstCaptures(topicBeforeActionPattern, in: text), captures.count == 2 {
            return meetingTitle(topic: captures[0], action: captures[1])
        }

        let topicAfterActionPattern = #"(?im)(?:主要|重点|共同)?\s*(研究|讨论|审议|评审|汇报|部署|推进|协调|沟通|交流|培训|复盘)\s*(?:的主题是|主题为|关于)?\s*([^，。；;\n]{2,32})"#
        if let captures = firstCaptures(topicAfterActionPattern, in: text), captures.count == 2 {
            return meetingTitle(topic: captures[1], action: captures[0])
        }

        let contentPattern = #"(?im)(?:会议)?(?:主要)?(?:内容|主题|议题)\s*(?:为|是|包括|:)\s*([^，。；;\n]{2,32})"#
        if let value = firstCapture(contentPattern, in: text) {
            return meetingTitle(topic: value, action: "")
        }

        let convenePattern = #"(?im)(?:召开|举行|组织|开展)\s*([^，。；;\n]{2,32}?)(?:会议|研讨会|讨论会|评审会|协调会|交流会|座谈会)"#
        if let value = firstCapture(convenePattern, in: text) {
            return meetingTitle(topic: value, action: "")
        }

        let ignoredPrefixes = ["各位", "大家", "起始时间", "时间", "日期", "地点", "地址", "参会", "与会", "会议链接", "腾讯会议", "链接", "联系人", "通知"]
        let candidates = text
            .components(separatedBy: CharacterSet(charactersIn: "\n。；;"))
            .map(cleanValue)
            .filter { value in
                guard value.count >= 2, !value.contains("://") else { return false }
                return !ignoredPrefixes.contains(where: { value.hasPrefix($0) })
            }

        if let candidate = candidates.first {
            return condensedTitle(from: candidate)
        }
        return "会议安排"
    }

    private func extractDate(from text: String, referenceDate: Date) -> (date: Date?, wasRecognized: Bool, warning: String?) {
        let startOfToday = calendar.startOfDay(for: referenceDate)

        let relativeDays: [(String, Int)] = [("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0)]
        for (token, offset) in relativeDays where text.contains(token) {
            return (calendar.date(byAdding: .day, value: offset, to: startOfToday), true, "识别到相对日期“\(token)”，请结合通知发送时间确认。")
        }

        if let captures = firstCaptures(#"(?<!\d)(\d{4})[年/.-](\d{1,2})[月/.-](\d{1,2})日?"#, in: text),
           captures.count == 3,
           let year = Int(captures[0]), let month = Int(captures[1]), let day = Int(captures[2]) {
            return (calendar.date(from: DateComponents(year: year, month: month, day: day)), true, nil)
        }

        if let captures = firstCaptures(#"(?<!\d)(\d{1,2})月(\d{1,2})[日号]?"#, in: text),
           captures.count == 2,
           let month = Int(captures[0]), let day = Int(captures[1]) {
            let currentYear = calendar.component(.year, from: referenceDate)
            let date = calendar.date(from: DateComponents(year: currentYear, month: month, day: day))
            return (date, true, nil)
        }

        if let captures = firstCaptures(#"(?<!\d)(\d{1,2})[/.](\d{1,2})(?!\d)"#, in: text),
            captures.count == 2,
           let month = Int(captures[0]), let day = Int(captures[1]), month <= 12, day <= 31 {
            let year = calendar.component(.year, from: referenceDate)
            return (calendar.date(from: DateComponents(year: year, month: month, day: day)), true, nil)
        }

        if let captures = firstCaptures(#"(下周|下星期|本周|这周|本星期|这星期|周|星期)([一二三四五六日天])"#, in: text), captures.count == 2 {
            let prefix = captures[0]
            let weekdayText = captures[1]
            let weekdayMap = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6]
            if let targetIndex = weekdayMap[weekdayText] {
                let appleWeekday = calendar.component(.weekday, from: startOfToday)
                let todayIndex = (appleWeekday + 5) % 7
                let daysToNextOccurrence = (targetIndex - todayIndex + 7) % 7
                var offset = daysToNextOccurrence
                if prefix == "下周" || prefix == "下星期" {
                    offset = 7 - todayIndex + targetIndex
                } else if prefix == "本周" || prefix == "这周" || prefix == "本星期" || prefix == "这星期" {
                    offset = targetIndex - todayIndex
                } else if prefix == "周" || prefix == "星期" {
                    offset = daysToNextOccurrence == 0 ? 7 : daysToNextOccurrence
                }
                let date = calendar.date(byAdding: .day, value: offset, to: startOfToday)
                return (date, true, "识别到相对星期“\(prefix)\(weekdayText)”，请结合通知发送时间确认。")
            }
        }

        return (nil, false, nil)
    }

    private func extractTimes(from text: String) -> (start: (hour: Int, minute: Int)?, end: (hour: Int, minute: Int)?) {
        let rangePatterns = [
            #"(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})[:：](\d{2})\s*(?:-|~|至|到)\s*(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})[:：](\d{2})"#,
            #"(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})点(?:(\d{1,2})分?)?\s*(?:-|~|至|到)\s*(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})点(?:(\d{1,2})分?)?"#
        ]

        for pattern in rangePatterns {
            if let captures = firstCapturesKeepingEmpty(pattern, in: text), captures.count == 6 {
                let startPeriod = captures[0]
                let endPeriod = captures[3].isEmpty ? startPeriod : captures[3]
                if let startHour = Int(captures[1]), let endHour = Int(captures[4]) {
                    let startMinute = Int(captures[2]) ?? 0
                    let endMinute = Int(captures[5]) ?? 0
                    return (
                        normalizeTime(hour: startHour, minute: startMinute, period: startPeriod),
                        normalizeTime(hour: endHour, minute: endMinute, period: endPeriod)
                    )
                }
            }
        }

        let singlePatterns = [
            #"(?:时间\s*:\s*)?(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})[:：](\d{2})"#,
            #"(?:时间\s*:\s*)?(上午|下午|晚上|中午|凌晨)?\s*(\d{1,2})点(?:(\d{1,2})分?)?"#
        ]
        for pattern in singlePatterns {
            if let captures = firstCapturesKeepingEmpty(pattern, in: text), captures.count == 3,
               let hour = Int(captures[1]) {
                return (normalizeTime(hour: hour, minute: Int(captures[2]) ?? 0, period: captures[0]), nil)
            }
        }
        return (nil, nil)
    }

    private func normalizeTime(hour: Int, minute: Int, period: String) -> (hour: Int, minute: Int)? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var normalizedHour = hour
        if ["下午", "晚上"].contains(period), hour < 12 { normalizedHour += 12 }
        if period == "中午", hour < 11 { normalizedHour += 12 }
        if period == "凌晨", hour == 12 { normalizedHour = 0 }
        return (normalizedHour, minute)
    }

    private func defaultStartTime(from text: String) -> (period: String, time: (hour: Int, minute: Int), displayTime: String)? {
        if text.contains("上午") {
            return ("上午", (9, 0), "09:00")
        }
        if text.contains("下午") {
            return ("下午", (14, 0), "14:00")
        }
        if text.contains("晚上") || text.contains("晚间") {
            return ("晚上", (18, 30), "18:30")
        }
        return nil
    }

    private func extractLabeledValue(from text: String, labels: [String], stoppingAt stopLabels: [String]) -> String {
        let escapedLabels = labels.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let escapedStops = stopLabels.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"(?im)^\s*(?:"# + escapedLabels + #")\s*:\s*(.+?)(?=\n\s*(?:"# + escapedStops + #")\s*:|\n|$)"#
        return firstCapture(pattern, in: text).map(cleanValue) ?? ""
    }

    private func extractAttendees(from text: String) -> String {
        let labeled = extractLabeledValue(
            from: text,
            labels: ["参会人员", "参会人", "与会人员", "参加人员", "参加人", "出席人员", "参会单位", "参加单位", "与会单位", "参会对象", "参会"],
            stoppingAt: ["时间", "日期", "地点", "地址", "联系人", "会议链接", "链接", "会议内容", "议题"]
        )
        if !labeled.isEmpty { return labeled }

        let sentencePatterns = [
            #"(?im)(?:请|邀请|通知)\s*([^。；;\n]{2,80}?)(?:参加|参会|出席|列席)"#,
            #"(?im)(?:参加|参会|出席|列席)(?:人员|对象|单位)?\s*(?:为|包括|有|:)\s*([^。；;\n]{2,80})"#,
            #"(?im)由\s*([^。；;\n]{2,80}?)(?:参加|参会|出席|列席)"#
        ]
        for pattern in sentencePatterns {
            if let captured = firstCapture(pattern, in: text) {
                let value = cleanAttendees(captured)
                if !value.isEmpty { return value }
            }
        }

        let unitPattern = #"[\p{Han}A-Za-z0-9·]{2,20}(?:公司|集团|部门|中心|办公室|委员会|团队|项目组|工作组|学院|学校|研究院|研究所|处|科|局|部)"#
        guard let regex = try? NSRegularExpression(pattern: unitPattern) else { return "" }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        var units: [String] = []
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let unit = String(text[range])
            if !units.contains(unit) { units.append(unit) }
            if units.count == 8 { break }
        }
        return units.joined(separator: "、")
    }

    private func cleanAttendees(_ rawValue: String) -> String {
        var value = cleanValue(rawValue)
        let removablePrefixes = ["各位", "相关", "以下", "上述"]
        for prefix in removablePrefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            value = cleanValue(value)
            break
        }
        value = value.replacingOccurrences(of: #"^(?:于|在)\s*\d{0,4}[^，,]{0,20}"#, with: "", options: .regularExpression)
        return cleanValue(value)
    }

    private func extractURL(from text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return "" }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url?.absoluteString ?? ""
    }

    private func date(bySetting time: (hour: Int, minute: Int), on date: Date) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) ?? date
    }

    private func meetingTitle(topic: String, action: String) -> String {
        var value = sanitizedTitleCore(topic)
        let suffixes = [
            "研究": "研究会", "讨论": "讨论会", "审议": "审议会", "评审": "评审会",
            "汇报": "汇报会", "部署": "部署会", "推进": "推进会", "协调": "协调会",
            "沟通": "沟通会", "交流": "交流会", "培训": "培训会", "复盘": "复盘会"
        ]
        if !value.hasSuffix("会"), !value.hasSuffix("会议"), let suffix = suffixes[action] {
            value += suffix
        } else if !value.hasSuffix("会"), !value.hasSuffix("会议") {
            value += "会议"
        }
        return condensedTitle(from: value)
    }

    private func condensedTitle(from rawValue: String) -> String {
        var value = sanitizedTitleCore(rawValue)
        if value.isEmpty { return "会议安排" }
        if value.count > 28 {
            value = String(value.prefix(28))
        }
        if !value.hasSuffix("会"), !value.hasSuffix("会议"), !value.contains("会") {
            value += "会议"
        }
        return value
    }

    private func sanitizedTitleCore(_ rawValue: String) -> String {
        var value = cleanValue(rawValue)
        let removablePrefixes = ["请大家", "请各位", "请相关人员", "请", "现定于", "兹定于", "计划", "拟"]
        for prefix in removablePrefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            value = cleanValue(value)
            break
        }
        value = value.replacingOccurrences(of: #"^(?:的主题是|主题为|关于)\s*"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?:请准时参加|请按时参加|请参加|届时参加)$"#, with: "", options: .regularExpression)
        value = cleanValue(value)

        return value
    }

    private func cleanValue(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "。；;，,")))
    }

    private func firstCapture(_ pattern: String, in text: String) -> String? {
        firstCaptures(pattern, in: text)?.first
    }

    private func firstCaptures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func firstCapturesKeepingEmpty(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}

struct MeetingSpeechFormatter {
    static func format(_ transcript: String) -> String {
        var value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields: [(label: String, pattern: String)] = [
            ("主要会议内容", "主要会议内容"),
            ("参会人员", "参会人员"),
            ("会议名称", "会议名称"),
            ("起始时间", "起始时间"),
            ("起始时间", #"(?<!起始)时间"#),
            ("日期", "日期"),
            ("地点", "地点")
        ]

        for field in fields {
            let escapedField = field.pattern.hasPrefix("(?<")
                ? field.pattern
                : NSRegularExpression.escapedPattern(for: field.pattern)
            let pattern = #"\s*"# + escapedField + #"\s*[：:]?\s*"#
            value = value.replacingOccurrences(
                of: pattern,
                with: "\n\(field.label)：",
                options: .regularExpression
            )
        }

        value = value.replacingOccurrences(
            of: #"[。；;，,]\s*\n"#,
            with: "\n",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
