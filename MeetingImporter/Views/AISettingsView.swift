import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var zhipuAPIKey = ""
    @State private var qwenAPIKey = ""
    @State private var alertMessage: String?
    @State private var dismissAfterAlert = false
    @State private var isTestingQwen = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("智谱 API Key", text: $zhipuAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("智谱 GLM-4.7-Flash")
                } footer: {
                    Text("主分析服务。密钥仅保存在本机系统钥匙串。")
                }

                Section {
                    Link("打开智谱 API Key 控制台", destination: URL(string: "https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys")!)

                    Button("删除已保存的密钥", role: .destructive) {
                        APIKeyStore.shared.deleteAPIKey(for: .zhipu)
                        zhipuAPIKey = ""
                        alertMessage = "已删除智谱密钥。"
                    }
                    .disabled(zhipuAPIKey.isEmpty && !APIKeyStore.shared.hasAPIKey(for: .zhipu))
                }

                Section {
                    SecureField("千问 API Key", text: $qwenAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("千问 qwen-flash（备用）")
                } footer: {
                    Text("智谱请求失败时自动调用千问；两家都不可用时再回退本地规则。")
                }

                Section {
                    Link("打开阿里云百炼 API Key 控制台", destination: URL(string: "https://bailian.console.aliyun.com/?tab=model#/api-key")!)

                    Button {
                        testQwenConnection()
                    } label: {
                        HStack {
                            Text("测试千问连接")
                            Spacer()
                            if isTestingQwen {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(
                        isTestingQwen ||
                        qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Button("删除千问密钥", role: .destructive) {
                        APIKeyStore.shared.deleteAPIKey(for: .qwen)
                        qwenAPIKey = ""
                        dismissAfterAlert = false
                        alertMessage = "已删除千问密钥。"
                    }
                    .disabled(qwenAPIKey.isEmpty && !APIKeyStore.shared.hasAPIKey(for: .qwen))
                }
            }
            .navigationTitle("AI 分析设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(
                            zhipuAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                            qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            .onAppear {
                zhipuAPIKey = APIKeyStore.shared.loadAPIKey(for: .zhipu) ?? ""
                qwenAPIKey = APIKeyStore.shared.loadAPIKey(for: .qwen) ?? ""
            }
            .alert("AI 设置", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") {
                    if dismissAfterAlert { dismiss() }
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            try APIKeyStore.shared.saveAPIKey(zhipuAPIKey, for: .zhipu)
            try APIKeyStore.shared.saveAPIKey(qwenAPIKey, for: .qwen)
            dismissAfterAlert = true
            alertMessage = "AI 密钥已安全保存。"
        } catch {
            dismissAfterAlert = false
            alertMessage = error.localizedDescription
        }
    }

    private func testQwenConnection() {
        let key = qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isTestingQwen = true
        dismissAfterAlert = false
        Task {
            do {
                let result = try await QwenAIService().analyze(
                    "明天下午召开项目进度协调会，请研发和设计负责人参加。",
                    apiKey: key,
                    referenceDate: Date()
                )
                alertMessage = "连接成功，千问返回会议名称：\(result.draft.title)"
            } catch {
                alertMessage = "千问连接失败：\(error.localizedDescription)"
            }
            isTestingQwen = false
        }
    }
}
