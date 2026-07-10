import Combine
import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    private let eventStore = EKEventStore()

    func save(_ draft: MeetingDraft) async throws {
        let granted = try await requestAccessIfNeeded()
        guard granted else { throw CalendarError.accessDenied }
        guard draft.endDate > draft.startDate else { throw CalendarError.invalidTimeRange }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.location = draft.location.nilIfBlank
        event.url = URL(string: draft.meetingURL.trimmingCharacters(in: .whitespacesAndNewlines))
        event.notes = draft.calendarNotes

        if let minutes = draft.reminderMinutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    private func requestAccessIfNeeded() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return true
        case .notDetermined:
            return try await eventStore.requestWriteOnlyAccessToEvents()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

enum CalendarError: LocalizedError {
    case accessDenied
    case invalidTimeRange

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "没有日历写入权限。请前往“设置 > 隐私与安全性 > 日历”允许访问。"
        case .invalidTimeRange:
            return "结束时间必须晚于开始时间。"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
