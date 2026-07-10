import SwiftUI

struct MeetingInputView: View {
    @StateObject private var speechService = SpeechInputService()
    @AppStorage("preferredAIProvider") private var preferredProviderRaw = AIProviderPreference.zhipu.rawValue
    @State private var sourceText = ""
    @State private var parsingResult: ParsingResult?
    @State private var isAnalyzing = false
    @State private var isZhipuConfigured = false
    @State private var isQwenConfigured = false
    @State private var showingAISettings = false
    @State private var showingInputExample = false
    @State private var isPressingVoiceInput = false
    @State private var speechTextPrefix = ""

    private let coordinator = MeetingAnalysisCoordinator()
    private let localParser = MeetingTextParser()

    private var isAIConfigured: Bool { isZhipuConfigured || isQwenConfigured }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    aiStatusCard
                    inputSection
                    privacyNote
                }
                .padding(.horizontal)
                .padding(.bottom)
                .padding(.top, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("会议通知")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $parsingResult) { result in
                MeetingReviewView(
                    initialDraft: result.draft,
                    recognizedFields: result.recognizedFields,
                    parsingMethod: result.method
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAISettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("AI 分析设置")
                }
            }
            .sheet(isPresented: $showingAISettings, onDismiss: refreshAIStatus) {
                AISettingsView()
            }
            .sheet(isPresented: $showingInputExample) {
                inputExampleSheet
            }
            .onAppear(perform: refreshAIStatus)
            .onDisappear {
                speechService.cancelRecording()
            }
            .onChange(of: speechService.transcript) { _, transcript in
                guard !transcript.isEmpty else { return }
                let formattedTranscript = MeetingSpeechFormatter.format(transcript)
                sourceText = speechTextPrefix.isEmpty
                    ? formattedTranscript
                    : "\(speechTextPrefix)\n\(formattedTranscript)"
            }
            .alert("语音输入", isPresented: Binding(
                get: { speechService.errorMessage != nil },
                set: { if !$0 { speechService.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(speechService.errorMessage ?? "")
            }
        }
    }

    private var aiStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: isAIConfigured ? "brain.head.profile.fill" : "brain.head.profile")
                .font(.title2)
                .foregroundStyle(isAIConfigured ? .purple : .secondary)
            Text("分析模型")
                .font(.subheadline.bold())
            Spacer()
            if isAIConfigured {
                Picker("分析模型", selection: selectedProviderBinding) {
                    if isZhipuConfigured {
                        Text(AIProviderPreference.zhipu.shortName)
                            .tag(AIProviderPreference.zhipu)
                    }
                    if isQwenConfigured {
                        Text(AIProviderPreference.qwen.shortName)
                            .tag(AIProviderPreference.qwen)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            promptCardBackground

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 30, height: 30)
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    Text("通知输入提示词")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("请依次说出字段名称和值：")
                    Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
                        GridRow {
                            Text("会议名称：…")
                            Text("日期：…")
                        }
                        GridRow {
                            Text("起始时间：…")
                            Text("地点：…")
                        }
                        GridRow {
                            Text("参会人员：…")
                            Text("主要会议内容：…")
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))

                HStack {
                    Spacer()
                    Button {
                        showingInputExample = true
                    } label: {
                        HStack(spacing: 5) {
                            Text("查看示例")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
            .padding(16)
        }
        .aspectRatio(1_423.0 / 721.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.blue.opacity(0.09), lineWidth: 1)
        }
    }

    private var promptCardBackground: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 1_423.0
            Image("PromptCardBackground")
                .resizable()
                .frame(width: 1_536.0 * scale, height: 1_024.0 * scale)
                .offset(x: -55.0 * scale, y: -127.0 * scale)
        }
        .accessibilityHidden(true)
    }

    private var inputExampleSheet: some View {
        NavigationStack {
            ScrollView {
                Text("""
                会议名称：办公会
                日期：2026年7月2日
                起始时间：09:00至10:00
                地点：教学楼A106会议室
                参会人员：办公室、财务部负责人
                主要会议内容：审议年度工作安排
                """)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("输入示例")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showingInputExample = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("会议通知原文")
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        analyze()
                    } label: {
                        if isAnalyzing {
                            ProgressView()
                        } else {
                            Text("分析导入")
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("导入") {
                        importDirectly()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .font(.subheadline)
                .buttonBorderShape(.roundedRectangle(radius: 9))
                .controlSize(.small)
                .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $sourceText)
                    .frame(minHeight: 230)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if sourceText.isEmpty {
                            Text("在这里粘贴完整通知……")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 19)
                                .allowsHitTesting(false)
                        }
                    }

                voiceInputControl
            }
            .padding()
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text(isAIConfigured
                     ? "分析导入：调用所选 AI，失败时自动使用备用模型。"
                     : "分析导入：配置 AI 密钥后可使用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
            }

            Label {
                Text("导入：仅由本机处理，不进行 AI 分析，直接导入日历。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.green)
            }
        }
    }

    private func analyze() {
        isAnalyzing = true
        let zhipuAPIKey = APIKeyStore.shared.loadAPIKey(for: .zhipu)
        let qwenAPIKey = APIKeyStore.shared.loadAPIKey(for: .qwen)
        Task {
            parsingResult = await coordinator.analyze(
                sourceText,
                zhipuAPIKey: zhipuAPIKey,
                qwenAPIKey: qwenAPIKey,
                preferredProvider: isAIConfigured ? selectedProvider : nil
            )
            isAnalyzing = false
        }
    }

    private func importDirectly() {
        speechService.stopRecording()
        parsingResult = localParser.parse(sourceText)
    }

    private func refreshAIStatus() {
        isZhipuConfigured = APIKeyStore.shared.hasAPIKey(for: .zhipu)
        isQwenConfigured = APIKeyStore.shared.hasAPIKey(for: .qwen)
        if selectedProvider == .zhipu && !isZhipuConfigured && isQwenConfigured {
            preferredProviderRaw = AIProviderPreference.qwen.rawValue
        } else if selectedProvider == .qwen && !isQwenConfigured && isZhipuConfigured {
            preferredProviderRaw = AIProviderPreference.zhipu.rawValue
        }
    }

    private var selectedProvider: AIProviderPreference {
        AIProviderPreference(rawValue: preferredProviderRaw) ?? .zhipu
    }

    private var selectedProviderBinding: Binding<AIProviderPreference> {
        Binding(
            get: { selectedProvider },
            set: { preferredProviderRaw = $0.rawValue }
        )
    }

    private var voiceInputControl: some View {
        Label(
            speechService.isRecording ? "松开结束语音输入" : "按住语音输入",
            systemImage: speechService.isRecording ? "waveform" : "mic.fill"
        )
        .font(.subheadline.bold())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(speechService.isRecording ? .white : .blue)
        .background(
            speechService.isRecording ? Color.red : Color.blue.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginVoiceInputIfNeeded() }
                .onEnded { _ in endVoiceInput() }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("按住开始识别，松开结束")
    }

    private func beginVoiceInputIfNeeded() {
        guard !isPressingVoiceInput else { return }
        isPressingVoiceInput = true
        speechTextPrefix = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await speechService.startRecording()
            if !isPressingVoiceInput {
                speechService.stopRecording()
            }
        }
    }

    private func endVoiceInput() {
        isPressingVoiceInput = false
        speechService.stopRecording()
    }

}

#Preview {
    MeetingInputView()
}
