import Foundation

struct MeetingDraft: Identifiable, Equatable, Hashable {
    let id = UUID()
    var title: String
    var originalText: String
    var startDate: Date
    var endDate: Date
    var location: String
    var meetingURL: String
    var attendees: String
    var reminderMinutes: Int?
    var warnings: [String]

    var calendarNotes: String {
        var sections: [String] = []

        if !attendees.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("参会人员\n\(attendees)")
        }

        if !meetingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("线上会议\n\(meetingURL)")
        }

        sections.append("会议通知原文\n\(originalText)")
        sections.append("由“会议通知”创建")
        return sections.joined(separator: "\n\n")
    }
}

struct ParsingResult: Hashable {
    var draft: MeetingDraft
    var recognizedFields: Set<RecognizedField>
    var method: ParsingMethod
}

enum ParsingMethod: String, Hashable {
    case zhipuAI
    case qwenAI
    case localRules
    case localFallback

    var displayName: String {
        switch self {
        case .zhipuAI: "智谱 AI"
        case .qwenAI: "千问 AI（备用）"
        case .localRules: "本地规则"
        case .localFallback: "本地规则（AI 已降级）"
        }
    }

    var isAI: Bool {
        self == .zhipuAI || self == .qwenAI
    }
}

enum RecognizedField: Hashable {
    case title
    case date
    case startTime
    case endTime
    case location
    case meetingURL
    case attendees
}
