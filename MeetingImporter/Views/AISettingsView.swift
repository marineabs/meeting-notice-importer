import SwiftUI

struct AISettingsView: View {
    private let privacyPolicyURL = URL(string: "https://marineabs.github.io/meeting-notice-importer/")!
    private let contactEmailURL = URL(string: "mailto:xwbj@hotmail.com")!
    private let zhipuConsoleURL = URL(string: "https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys")!
    private let openRouterConsoleURL = URL(string: "https://openrouter.ai/keys")!

    @Environment(\.dismiss) private var dismiss
    @State private var zhipuAPIKey = ""
    @State private var openRouterAPIKey = ""
    @State private var alertMessage: String?
    @State private var dismissAfterAlert = false
    @State private var testingProvider: AIProviderKey?
    @State private var pendingAPIKeyDeletion: AIProviderKey?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("密钥仅保存在本机系统钥匙串中。使用智能导出时，通知原文会发送给所选服务商进行结构化提取。", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    providerHeader(title: "智谱 GLM-4.7-Flash", subtitle: "免费文本模型 · 默认优先", icon: "sparkles", color: .purple)
                    SecureField("智谱 API Key", text: $zhipuAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("获取或管理智谱 API Key", destination: zhipuConsoleURL)
                    providerActions(for: .zhipu, apiKey: zhipuAPIKey)
                } footer: {
                    Text("高峰期可能触发限流；App 将自动尝试已配置的 OpenRouter 备用服务，再回退本地规则。")
                }

                Section {
                    providerHeader(title: "OpenRouter 免费模型", subtitle: "免费备用 · 免费模型池与限流会变化", icon: "globe", color: .blue)
                    SecureField("OpenRouter API Key", text: $openRouterAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("注册 OpenRouter 并获取 API Key", destination: openRouterConsoleURL)
                    providerActions(for: .openRouter, apiKey: openRouterAPIKey)
                }

                Section("使用说明") {
                    Label("智能导出失败时自动使用下一个已配置服务；全部失败后改用本地规则。", systemImage: "arrow.triangle.2.circlepath")
                    Label("立即导出始终只使用本地规则，不会发送通知原文。", systemImage: "lock")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Section("关于与支持") {
                    Link(destination: contactEmailURL) { Label("联系我们", systemImage: "envelope") }
                    Link(destination: privacyPolicyURL) { Label("隐私政策", systemImage: "hand.raised") }
                    Label {
                        HStack(spacing: 8) {
                            Text("软件版本")
                            Text(appVersion).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.blue)
                    }
                }
            }
            .navigationTitle("智能分析设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .onAppear {
                zhipuAPIKey = APIKeyStore.shared.loadAPIKey(for: .zhipu) ?? ""
                openRouterAPIKey = APIKeyStore.shared.loadAPIKey(for: .openRouter) ?? ""
            }
            .alert("AI 设置", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") { if dismissAfterAlert { dismiss() } }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog(
                "确认删除 API Key？",
                isPresented: Binding(
                    get: { pendingAPIKeyDeletion != nil },
                    set: { if !$0 { pendingAPIKeyDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingAPIKeyDeletion
            ) { provider in
                Button("删除\(providerName(provider))密钥", role: .destructive) { deleteAPIKey(for: provider) }
                Button("取消", role: .cancel) {}
            } message: { provider in
                Text("删除后将无法使用\(providerName(provider))进行智能导出，除非重新填写并保存密钥。")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    @ViewBuilder
    private func providerHeader(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func providerActions(for provider: AIProviderKey, apiKey: String) -> some View {
        Button {
            testConnection(for: provider, apiKey: apiKey)
        } label: {
            HStack {
                Text("测试\(providerName(provider))连接")
                Spacer()
                if testingProvider == provider { ProgressView() }
            }
        }
        .disabled(testingProvider != nil || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Button("删除\(providerName(provider))密钥", role: .destructive) {
            dismissAfterAlert = false
            pendingAPIKeyDeletion = provider
        }
        .disabled(apiKey.isEmpty && !APIKeyStore.shared.hasAPIKey(for: provider))
    }

    private func providerName(_ provider: AIProviderKey) -> String {
        switch provider {
        case .zhipu: "智谱"
        case .openRouter: "OpenRouter"
        }
    }

    private func deleteAPIKey(for provider: AIProviderKey) {
        APIKeyStore.shared.deleteAPIKey(for: provider)
        switch provider {
        case .zhipu: zhipuAPIKey = ""
        case .openRouter: openRouterAPIKey = ""
        }
        pendingAPIKeyDeletion = nil
        alertMessage = "已删除\(providerName(provider))密钥。"
    }

    private func save() {
        do {
            try APIKeyStore.shared.saveAPIKey(zhipuAPIKey, for: .zhipu)
            try APIKeyStore.shared.saveAPIKey(openRouterAPIKey, for: .openRouter)
            dismissAfterAlert = true
            alertMessage = "AI 密钥已安全保存。"
        } catch {
            dismissAfterAlert = false
            alertMessage = error.localizedDescription
        }
    }

    private func testConnection(for provider: AIProviderKey, apiKey: String) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        testingProvider = provider
        dismissAfterAlert = false
        Task {
            do {
                let referenceDate = Date()
                let result: ParsingResult
                switch provider {
                case .zhipu:
                    result = try await ZhipuAIService().analyze(
                        "明天下午召开项目进度协调会，请研发和设计负责人参加。",
                        apiKey: key,
                        referenceDate: referenceDate
                    )
                case .openRouter:
                    result = try await OpenRouterAIService().analyze(
                        "明天下午召开项目进度协调会，请研发和设计负责人参加。",
                        apiKey: key,
                        referenceDate: referenceDate
                    )
                }
                alertMessage = "连接成功，\(providerName(provider))返回会议名称：\(result.draft.title)"
            } catch {
                alertMessage = "\(providerName(provider))连接失败：\(error.localizedDescription)"
            }
            testingProvider = nil
        }
    }
}
