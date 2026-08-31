import Foundation

// MARK: - HTTP transport (injectable for tests)

protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum HTTPTransportError: Error {
    case noResponse
    case unsuccessful(Int, String)
}

// MARK: - ARK API client (data/ArkApiClient.kt)

enum ArkEndpointKind {
    static let responses = "responses"
    static let chatCompletions = "chat/completions"

    static func resolve(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.contains("chat/completions") ? chatCompletions : responses
    }
}

final class ArkApiClient {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.shared) {
        self.transport = transport
    }

    func isConfigured(_ config: ArkRuntimeConfig = ArkApiClient.defaultConfig()) -> Bool {
        return !config.apiKey.isEmpty
    }

    static func defaultConfig() -> ArkRuntimeConfig {
        let settings = RuntimeSettings.defaults()
        return ArkRuntimeConfig(
            apiKey: settings.arkApiKey,
            model: settings.arkModel,
            baseUrl: settings.arkBaseUrl,
            endpoint: settings.arkEndpoint,
            systemPrompt: settings.arkSystemPrompt
        )
    }

    func generateReply(messages: [ArkRequestMessage], config: ArkRuntimeConfig) async -> Result<String, Error> {
        if messages.isEmpty {
            return .failure(ArgumentError("消息列表为空"))
        }
        guard isConfigured(config) else {
            return .failure(IllegalStateError("请先在设置中配置 ARK_API_KEY"))
        }
        do {
            let endpoint = ArkEndpointKind.resolve(config.endpoint)
            let body = buildRequestBody(endpoint: endpoint, messages: messages, config: config, stream: false)
            let request = makeRequest(endpoint: endpoint, config: config, body: body)
            let (data, response) = try await transport.send(request)
            guard response.statusCode >= 200 && response.statusCode < 300 else {
                let message = extractErrorMessage(String(data: data, encoding: .utf8) ?? "")
                return .failure(IllegalStateError("ARK 请求失败 (\(response.statusCode)): \(message)"))
            }
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            let text = parseAssistantText(endpoint: endpoint, body: bodyString)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(IllegalStateError("ARK 返回为空，请稍后重试"))
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    func generateReplyStream(
        messages: [ArkRequestMessage],
        config: ArkRuntimeConfig,
        onDelta: @escaping (String) -> Void,
        onReasoningDelta: ((String) -> Void)? = nil
    ) async -> Result<String, Error> {
        if messages.isEmpty {
            return .failure(ArgumentError("消息列表为空"))
        }
        guard isConfigured(config) else {
            return .failure(IllegalStateError("请先在设置中配置 ARK_API_KEY"))
        }
        do {
            let endpoint = ArkEndpointKind.resolve(config.endpoint)
            let body = buildRequestBody(endpoint: endpoint, messages: messages, config: config, stream: true)
            let request = makeRequest(endpoint: endpoint, config: config, body: body)
            let (data, response) = try await transport.send(request)
            guard response.statusCode >= 200 && response.statusCode < 300 else {
                let message = extractErrorMessage(String(data: data, encoding: .utf8) ?? "")
                return .failure(IllegalStateError("ARK 请求失败 (\(response.statusCode)): \(message)"))
            }
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            let text = parseAssistantTextStream(endpoint: endpoint, body: bodyString, onDelta: onDelta, onReasoningDelta: onReasoningDelta)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(IllegalStateError("ARK 返回为空，请稍后重试"))
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    func generateReplyWithImages(
        prompt: String,
        images: [ImagePayload],
        config: ArkRuntimeConfig = ArkApiClient.defaultConfig(),
        stream: Bool = false,
        onDelta: ((String) -> Void)? = nil,
        onReasoningDelta: ((String) -> Void)? = nil
    ) async -> Result<String, Error> {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPrompt.isEmpty {
            return .failure(ArgumentError("图片提问提示词为空"))
        }
        let normalizedImages = images.filter { !$0.bytes.isEmpty }
        if normalizedImages.isEmpty {
            return .failure(ArgumentError("图片数据为空"))
        }
        guard isConfigured(config) else {
            return .failure(IllegalStateError("请先在设置中配置 ARK_API_KEY"))
        }
        do {
            let endpoint = ArkEndpointKind.resolve(config.endpoint)
            let body = buildImageRequestBody(endpoint: endpoint, prompt: normalizedPrompt, images: normalizedImages, config: config, stream: stream)
            let request = makeRequest(endpoint: endpoint, config: config, body: body)
            let (data, response) = try await transport.send(request)
            guard response.statusCode >= 200 && response.statusCode < 300 else {
                let message = extractErrorMessage(String(data: data, encoding: .utf8) ?? "")
                return .failure(IllegalStateError("ARK 图片请求失败 (\(response.statusCode)): \(message)"))
            }
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            if stream {
                let text = parseAssistantTextStream(endpoint: endpoint, body: bodyString, onDelta: onDelta ?? { _ in }, onReasoningDelta: onReasoningDelta)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .failure(IllegalStateError("ARK 图片识别返回为空，请稍后重试"))
                }
                return .success(text)
            }
            let text = parseAssistantText(endpoint: endpoint, body: bodyString)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(IllegalStateError("ARK 图片识别返回为空，请稍后重试"))
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Request building

    private func makeRequest(endpoint: String, config: ArkRuntimeConfig, body: String) -> URLRequest {
        let url = URL(string: endpointUrl(endpoint: endpoint, config: config))!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 300
        return request
    }

    private func endpointUrl(endpoint: String, config: ArkRuntimeConfig) -> String {
        let base = config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/\(endpoint)"
    }

    private func buildRequestBody(endpoint: String, messages: [ArkRequestMessage], config: ArkRuntimeConfig, stream: Bool) -> String {
        let normalized = messages.compactMap { message -> ArkRequestMessage? in
            let role = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let content = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { return nil }
            return ArkRequestMessage(role: role, text: content)
        }
        let prompt = config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalMessages: [ArkRequestMessage] = []
        if !prompt.isEmpty { finalMessages.append(ArkRequestMessage(role: "system", text: prompt)) }
        finalMessages.append(contentsOf: normalized)

        if endpoint == ArkEndpointKind.responses {
            var input: [[String: Any]] = []
            for message in finalMessages {
                input.append([
                    "role": message.role,
                    "content": [["type": "input_text", "text": message.text]]
                ])
            }
            let root: [String: Any] = [
                "model": config.model,
                "input": input,
                "temperature": 0.7,
                "stream": stream
            ]
            return JSON.string(root)
        } else {
            let chatMessages = finalMessages.map { ["role": $0.role, "content": $0.text] as [String: Any] }
            let root: [String: Any] = [
                "model": config.model,
                "messages": chatMessages,
                "temperature": 0.7,
                "stream": stream
            ]
            return JSON.string(root)
        }
    }

    private func buildImageRequestBody(endpoint: String, prompt: String, images: [ImagePayload], config: ArkRuntimeConfig, stream: Bool) -> String {
        let dataUrls = images.map { image -> String in
            "data:\(image.mimeType);base64,\(image.bytes.base64EncodedString())"
        }
        let systemPrompt = config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if endpoint == ArkEndpointKind.responses {
            var input: [[String: Any]] = []
            if !systemPrompt.isEmpty {
                input.append([
                    "role": "system",
                    "content": [["type": "input_text", "text": systemPrompt]]
                ])
            }
            var userContent: [[String: Any]] = []
            for dataUrl in dataUrls {
                userContent.append(["type": "input_image", "image_url": dataUrl])
            }
            userContent.append(["type": "input_text", "text": prompt])
            input.append(["role": "user", "content": userContent])
            return JSON.string([
                "model": config.model,
                "input": input,
                "temperature": 0.7,
                "stream": stream
            ])
        } else {
            var messages: [[String: Any]] = []
            if !systemPrompt.isEmpty {
                messages.append(["role": "system", "content": systemPrompt])
            }
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            for dataUrl in dataUrls {
                content.append(["type": "image_url", "image_url": ["url": dataUrl]])
            }
            messages.append(["role": "user", "content": content])
            return JSON.string([
                "model": config.model,
                "messages": messages,
                "temperature": 0.7,
                "stream": stream
            ])
        }
    }

    // MARK: - Response parsing

    private func parseAssistantText(endpoint: String, body: String) -> String {
        guard let root = JSON.parse(body) else { return "" }

        if endpoint == ArkEndpointKind.responses {
            let outputText = optString(root, key: "output_text")
            if !outputText.isEmpty { return outputText }
            if let output = optArray(root, key: "output") {
                for item in output {
                    if let contentArray = optArray(item, key: "content") {
                        let parsed = extractTextFromContentArray(contentArray)
                        if !parsed.isEmpty { return parsed }
                    }
                }
            }
        }

        if let choices = optArray(root, key: "choices"), !choices.isEmpty {
            if let message = optObjectAny(choices[0], key: "message") {
                let content = optObjectAny(message, key: "content")
                if let s = content as? String, !s.isEmpty {
                    return s
                }
                if let array = content as? [Any] {
                    let parsed = extractTextFromContentArray(array)
                    if !parsed.isEmpty { return parsed }
                }
            }
        }
        return ""
    }

    private struct StreamPayload {
        let delta: String
        let fallbackText: String
        let reasoningDelta: String
        let reasoningFallback: String
    }

    private func parseAssistantTextStream(endpoint: String, body: String, onDelta: (String) -> Void, onReasoningDelta: ((String) -> Void)?) -> String {
        // 兜底：部分兼容端点会忽略 stream:true，直接返回普通 JSON（非 SSE）。
        // 此时按整段解析并作为一次 delta 输出，避免“返回为空”把内容吞掉。
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.contains("data:") {
            let whole = parseAssistantText(endpoint: endpoint, body: body)
            if !whole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onDelta(whole)
                return whole
            }
        }

        var aggregate = ""
        var fallbackText = ""
        var reasoningAggregate = ""
        var reasoningFallback = ""

        let lines = body.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for lineRaw in lines {
            let line = String(lineRaw).trimmingCharacters(in: CharacterSet(charactersIn: "\r\n " ))
            var payload = ""
            if line.hasPrefix("data:") {
                payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("event:") || line.hasPrefix(":") || line.isEmpty {
                payload = ""
            } else {
                payload = line
            }
            if payload.isEmpty || payload == "[DONE]" { continue }

            let parsed = parseStreamPayload(endpoint: endpoint, payload: payload)
            if !parsed.delta.isEmpty {
                aggregate += parsed.delta
                onDelta(parsed.delta)
            }
            if !parsed.reasoningDelta.isEmpty {
                reasoningAggregate += parsed.reasoningDelta
                onReasoningDelta?(parsed.reasoningDelta)
            }
            if !parsed.fallbackText.isEmpty { fallbackText = parsed.fallbackText }
            if !parsed.reasoningFallback.isEmpty { reasoningFallback = parsed.reasoningFallback }
        }

        if reasoningAggregate.isEmpty && !reasoningFallback.isEmpty {
            onReasoningDelta?(reasoningFallback)
        }

        return aggregate.isEmpty ? fallbackText : aggregate
    }

    private func parseStreamPayload(endpoint: String, payload: String) -> StreamPayload {
        guard let root = JSON.parse(payload) else {
            return StreamPayload(delta: "", fallbackText: "", reasoningDelta: "", reasoningFallback: "")
        }
        return endpoint == ArkEndpointKind.responses
            ? parseResponsesStreamPayload(root)
            : parseChatCompletionsStreamPayload(root)
    }

    private func parseResponsesStreamPayload(_ root: Any?) -> StreamPayload {
        let type = optString(root, key: "type")
        var delta = ""
        var reasoningDelta = ""
        if type == "response.output_text.delta" { delta = optString(root, key: "delta") }
        if type == "response.reasoning_summary_text.delta" { reasoningDelta = optString(root, key: "delta") }

        let responseObject = optObjectAny(root, key: "response")
        var fallback = ""
        if type == "response.output_text.done" {
            fallback = optString(root, key: "text")
        } else if type == "response.completed" {
            fallback = optString(root, key: "output_text")
        } else if let s = optString(responseObject, key: "output_text").trimOrNull(), !s.isEmpty {
            fallback = s
        }

        var reasoningFallback = ""
        if type == "response.reasoning_summary_text.done" {
            reasoningFallback = optString(root, key: "text")
        } else if type == "response.reasoning_summary_part.done" {
            reasoningFallback = optString(optObjectAny(root, key: "part"), key: "text")
        } else if type == "response.completed" {
            reasoningFallback = extractReasoningSummary(optObjectAny(root, key: "response"))
        } else {
            reasoningFallback = extractReasoningSummary(responseObject)
        }

        return StreamPayload(delta: delta, fallbackText: fallback, reasoningDelta: reasoningDelta, reasoningFallback: reasoningFallback)
    }

    private func parseChatCompletionsStreamPayload(_ root: Any?) -> StreamPayload {
        guard let choices = optArray(root, key: "choices"), !choices.isEmpty else {
            return StreamPayload(delta: "", fallbackText: "", reasoningDelta: "", reasoningFallback: "")
        }
        let firstChoice = choices[0]
        let deltaObj = optObjectAny(firstChoice, key: "delta")
        let deltaValue = optObjectAny(deltaObj, key: "content")
        var delta = ""
        if let s = deltaValue as? String {
            delta = s
        } else if let array = deltaValue as? [Any] {
            delta = extractTextFromContentArray(array)
        }
        let fallback = optString(firstChoice, key: "text")
        return StreamPayload(delta: delta, fallbackText: fallback, reasoningDelta: "", reasoningFallback: "")
    }

    private func extractReasoningSummary(_ response: Any?) -> String {
        guard let output = optArray(response, key: "output") else { return "" }
        for item in output {
            if optString(item, key: "type") != "reasoning" { continue }
            if let summary = optArray(item, key: "summary") {
                let text = extractTextFromContentArray(summary)
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    private func extractTextFromContentArray(_ array: [Any]) -> String {
        var chunks: [String] = []
        for part in array {
            if let s = part as? String, !s.isEmpty {
                chunks.append(s)
            } else if let dict = part as? [String: Any] {
                let text = optString(dict, key: "text")
                if !text.isEmpty { chunks.append(text) }
            }
        }
        return chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractErrorMessage(_ body: String) -> String {
        if body.isEmpty { return "空响应" }
        guard let root = JSON.parse(body) else { return String(body.prefix(280)) }
        if let error = optObjectAny(root, key: "error") {
            let message = optString(error, key: "message")
            if !message.isEmpty { return message }
        }
        let rootMessage = optString(root, key: "message")
        if !rootMessage.isEmpty { return rootMessage }
        return String(body.prefix(280))
    }
}

// MARK: - Errors

struct ArgumentError: Error, LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { return message } }
struct IllegalStateError: Error, LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { return message } }

// MARK: - URLSession transport

final class URLSessionTransport: HTTPTransport {
    static let shared = URLSessionTransport()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPTransportError.noResponse }
        return (data, http)
    }
}
