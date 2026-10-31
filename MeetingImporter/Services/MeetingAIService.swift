import Foundation

enum AIProviderPreference: String, CaseIterable, Identifiable {
    case zhipu
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhipu: "智谱 GLM-4.7-Flash"
        case .openRouter: "OpenRouter 免费模型"
        }
    }

    var shortName: String {
        switch self {
        case .zhipu: "智谱"
        case .openRouter: "OpenRouter"
        }
    }

    var backup: AIProviderPreference {
        self == .zhipu ? .openRouter : .zhipu
    }
}

struct MeetingAnalysisCoordinator {
    private let localParser = MeetingTextParser()
    private let zhipuService = ZhipuAIService()
    private let openRouterService = OpenRouterAIService()

    func analyze(
        _ text: String,
        zhipuAPIKey: String?,
        openRouterAPIKey: String?,
        preferredProvider: AIProviderPreference?,
        referenceDate: Date = Date()
    ) async -> ParsingResult {
        var failures: [String] = []
        let hasZhipu = hasValue(zhipuAPIKey)
        let hasOpenRouter = hasValue(openRouterAPIKey)
        let providerOrder = preferredProvider.map { [$0, $0.backup] } ?? []

        for provider in providerOrder {
            do {
                var result: ParsingResult
                switch provider {
                case .zhipu:
                    guard let zhipuAPIKey, hasZhipu else { continue }
                    result = try await zhipuService.analyze(text, apiKey: zhipuAPIKey, referenceDate: referenceDate)
                case .openRouter:
                    guard let openRouterAPIKey, hasOpenRouter else { continue }
                    result = try await openRouterService.analyze(text, apiKey: openRouterAPIKey, referenceDate: referenceDate)
                }

                if provider != preferredProvider, let preferredProvider {
                    result.draft.warnings.insert(
                        "\(preferredProvider.displayName) 本次未响应，已由 \(provider.displayName) 备用服务完成分析。",
                        at: 0
                    )
                }
                return result
            } catch {
                failures.append("\(provider.displayName)：\(error.localizedDescription)")
            }
        }

        var fallback = localParser.parse(text, referenceDate: referenceDate)
        if hasZhipu || hasOpenRouter {
            fallback.method = .localFallback
            let detail: String
            if preferredProvider == nil {
                detail = "未选择 AI 模型。"
            } else {
                detail = failures.isEmpty ? "已选择的 AI 服务暂时不可用。" : failures.joined(separator: "；")
            }
            fallback.draft.warnings.insert("AI 服务暂时不可用，已自动改用本地规则。\(detail)", at: 0)
        }
        return fallback
    }

    private func hasValue(_ value: String?) -> Bool {
        !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct OpenRouterAIService {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let model = "openrouter/free"

    func analyze(_ text: String, apiKey: String, referenceDate: Date) async throws -> ParsingResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenRouterChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: MeetingAIPrompt.system(referenceDate: referenceDate)),
                .init(role: "user", content: MeetingAIPrompt.user(text: text))
            ],
            temperature: 0.1
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterAIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data)
            throw OpenRouterAIError.api(status: httpResponse.statusCode, message: apiError?.message ?? apiError?.error?.message)
        }

        let chatResponse = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content,
              let contentData = AIResponseContentDecoder.jsonData(from: content) else {
            throw OpenRouterAIError.missingContent
        }

        let payload: AIMeetingPayload
        do {
            payload = try JSONDecoder().decode(AIMeetingPayload.self, from: contentData)
        } catch {
            throw OpenRouterAIError.invalidJSON
        }

        return MeetingAIResultMapper().map(
            payload,
            originalText: text,
            referenceDate: referenceDate,
            method: .openRouterAI
        )
    }
}

private struct OpenRouterChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenRouterChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct OpenRouterErrorResponse: Decodable {
    let message: String?
    let error: APIError?

    struct APIError: Decodable {
        let message: String?
    }
}

enum OpenRouterAIError: LocalizedError {
    case invalidResponse
    case api(status: Int, message: String?)
    case missingContent
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器响应无效。"
        case .api(let status, let message):
            "接口返回 \(status)\(message.map { "：\($0)" } ?? "")."
        case .missingContent:
            "接口没有返回分析内容。"
        case .invalidJSON:
            "接口返回的数据格式无法解析。"
        }
    }
}
