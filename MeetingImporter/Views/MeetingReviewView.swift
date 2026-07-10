import SwiftUI
import UIKit

struct MeetingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var calendarService = CalendarService()
    @State private var draft: MeetingDraft
    @State private var isSaving = false
    @State private var alert: SaveAlert?

    let recognizedFields: Set<RecognizedField>

    init(initialDraft: MeetingDraft, recognizedFields: Set<RecognizedField>, parsingMethod: ParsingMethod) {
        _draft = State(initialValue: initialDraft)
        self.recognizedFields = recognizedFields
    }

    var body: some View {
        Form {
            Section("会议信息") {
                TextField("会议主题", text: $draft.title)

                DatePicker("开始", selection: $draft.startDate)
                DatePicker("结束", selection: $draft.endDate, in: draft.startDate...)

                TextField("地点（可选）", text: $draft.location)
                TextField("线上会议链接（可选）", text: $draft.meetingURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("参会人员（可选）", text: $draft.attendees, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("提醒") {
                Picker("提前提醒", selection: $draft.reminderMinutes) {
                    Text("不提醒").tag(Int?.none)
                    Text("提前 5 分钟").tag(Int?.some(5))
                    Text("提前 10 分钟").tag(Int?.some(10))
                    Text("提前 15 分钟").tag(Int?.some(15))
                    Text("提前 30 分钟").tag(Int?.some(30))
                    Text("提前 1 小时").tag(Int?.some(60))
                    Text("提前 1 天").tag(Int?.some(1_440))
                }
            }

            Section {
                Text(draft.originalText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("原始通知")
            } footer: {
                Text("会议通知原文会完整写入日历备注。")
            }

            Section {
                Button {
                    saveToCalendar()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("写入并打开系统日历", systemImage: "calendar.badge.plus")
                        }
                        Spacer()
                    }
                }
                .disabled(!canSave || isSaving)
            }

            if !draft.warnings.isEmpty {
                warningSection
            }
        }
        .navigationTitle("确认会议信息")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(alert.isSuccess ? "完成" : "知道了")) {
                    if alert.isSuccess { dismiss() }
                }
            )
        }
    }

    private var warningSection: some View {
        Section {
            ForEach(draft.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("特别提示")
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.endDate > draft.startDate
    }

    private func saveToCalendar() {
        isSaving = true
        Task {
            do {
                try await calendarService.save(draft)
                let opened = await openSystemCalendar(at: draft.startDate)
                if opened {
                    dismiss()
                } else {
                    alert = SaveAlert(
                        title: "已写入日历",
                        message: "会议“\(draft.title)”已保存成功，但系统日历未能自动打开。",
                        isSuccess: true
                    )
                }
            } catch {
                alert = SaveAlert(title: "无法写入日历", message: error.localizedDescription, isSuccess: false)
            }
            isSaving = false
        }
    }

    @MainActor
    private func openSystemCalendar(at date: Date) async -> Bool {
        let interval = date.timeIntervalSinceReferenceDate
        guard let url = URL(string: "calshow:\(interval)") else { return false }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }
}

private struct SaveAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isSuccess: Bool
}
