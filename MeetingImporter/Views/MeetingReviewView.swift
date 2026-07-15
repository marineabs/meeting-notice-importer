import SwiftUI
import UIKit

struct MeetingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var calendarService = CalendarService()
    @State private var draft: MeetingDraft
    @State private var isSaving = false
    @State private var alert: SaveAlert?
    @State private var isOriginalTextExpanded = false

    let recognizedFields: Set<RecognizedField>

    init(initialDraft: MeetingDraft, recognizedFields: Set<RecognizedField>, parsingMethod: ParsingMethod) {
        _draft = State(initialValue: initialDraft)
        self.recognizedFields = recognizedFields
    }

    var body: some View {
        Form {
            Section("会议信息") {
                LabeledContent("会议名称") {
                    TextField("请输入会议名称", text: $draft.title)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("开始日期")
                    Spacer()
                    DatePicker("", selection: startDateBinding, displayedComponents: .date)
                        .labelsHidden()
                    Text(weekdayText(for: draft.startDate))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("截止日期")
                    Spacer()
                    DatePicker("", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                        .labelsHidden()
                    Text(weekdayText(for: draft.endDate))
                        .foregroundStyle(.secondary)
                }

                DatePicker("开始时间", selection: startDateBinding, displayedComponents: .hourAndMinute)
                DatePicker("结束时间", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .hourAndMinute)

                LabeledContent("会议地点") {
                    TextField("未填写", text: $draft.location)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("参会人员") {
                    TextField("未填写", text: $draft.attendees, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2...4)
                }

                LabeledContent("线上会议链接") {
                    TextField("未填写", text: $draft.meetingURL)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
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

            if !draft.warnings.isEmpty {
                warningSection
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

            Section {
                DisclosureGroup(
                    isOriginalTextExpanded ? "收起原始通知" : "查看原始通知",
                    isExpanded: $isOriginalTextExpanded
                ) {
                    Text(draft.originalText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                }
            } header: {
                Text("原始通知")
            } footer: {
                Text("会议通知原文会完整写入日历备注。")
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

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { draft.startDate },
            set: { newStartDate in
                let existingDuration = draft.endDate.timeIntervalSince(draft.startDate)
                let preservedDuration = existingDuration > 0 ? existingDuration : 3_600
                draft.startDate = newStartDate
                draft.endDate = newStartDate.addingTimeInterval(preservedDuration)
            }
        )
    }

    private func weekdayText(for date: Date) -> String {
        let symbols = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let weekday = Calendar.current.component(.weekday, from: date)
        return "（\(symbols[weekday - 1])）"
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
