import Foundation

struct ZhipuAIService {
    private let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!

    func analyze(_ text: String, apiKey: String, referenceDate: Date) async throws -> ParsingResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(makeRequest(text: text, referenceDate: referenceDate))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZhipuAIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(ZhipuErrorResponse.self, from: data)
            throw ZhipuAIError.api(status: httpResponse.statusCode, message: apiError?.error.message)
        }

        let chatResponse = try JSONDecoder().decode(ZhipuChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content,
              let contentData = AIResponseContentDecoder.jsonData(from: content) else {
            throw ZhipuAIError.missingContent
        }

        let payload: AIMeetingPayload
        do {
            payload = try JSONDecoder().decode(AIMeetingPayload.self, from: contentData)
        } catch {
            throw ZhipuAIError.invalidJSON
        }
        return MeetingAIResultMapper().map(
            payload,
            originalText: text,
            referenceDate: referenceDate,
            method: .zhipuAI
        )
    }

    private func makeRequest(text: String, referenceDate: Date) -> ZhipuChatRequest {
        return ZhipuChatRequest(
            model: "glm-4.7-flash",
            messages: [
                .init(role: "system", content: MeetingAIPrompt.system(referenceDate: referenceDate)),
                .init(role: "user", content: MeetingAIPrompt.user(text: text))
            ],
            responseFormat: .init(type: "json_object"),
            thinking: .init(type: "disabled"),
            temperature: 0.1
        )
    }

}

private struct ZhipuChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat
    let thinking: Thinking
    let temperature: Double

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    struct Thinking: Encodable {
        let type: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, thinking, temperature
        case responseFormat = "response_format"
    }
}

private struct ZhipuChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct ZhipuErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String?
    }
}

enum ZhipuAIError: LocalizedError {
    case invalidResponse
    case api(status: Int, message: String?)
    case missingContent
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器响应无效。"
        case .api(let status, let message):
            "接口返回 \(status)\(message.map { "：\($0)" } ?? "")。"
        case .missingContent:
            "接口没有返回分析内容。"
        case .invalidJSON:
            "接口返回的数据格式无法解析。"
        }
    }
}
