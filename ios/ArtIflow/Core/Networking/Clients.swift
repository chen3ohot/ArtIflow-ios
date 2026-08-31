import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - FlowStudy sync client (data/FlowStudySyncClient.kt)

struct FlowStudyPairResponse {
    let deviceToken: String
    let userId: String
}

struct FlowStudyPushResponse {
    let insertedSessions: Int
    let updatedSessions: Int
    let skippedSessions: Int
    let importBatchId: String
}

final class FlowStudySyncClient {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.shared) {
        self.transport = transport
    }

    func pairDevice(serverUrl: String, pairCode: String, deviceId: String) async -> Result<FlowStudyPairResponse, Error> {
        let baseUrl = normalizeServerUrl(serverUrl)
        if baseUrl.isEmpty { return .failure(ArgumentError("FlowStudy 地址为空")) }
        if pairCode.isEmpty { return .failure(ArgumentError("配对码为空")) }
        if deviceId.isEmpty { return .failure(ArgumentError("device_id 为空")) }

        do {
            let url = URL(string: "\(baseUrl)/api/devices/pair")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "pair_code": pairCode.trimmingCharacters(in: .whitespacesAndNewlines),
                "device_id": deviceId,
                "device_name": defaultDeviceName()
            ]
            request.httpBody = JSON.data(body)
            let (data, response) = try await transport.send(request)
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            guard response.statusCode >= 200 && response.statusCode < 300 else {
                let detail = parseErrorDetail(bodyString)
                return .failure(IllegalStateError("配对失败 (\(response.statusCode)): \(detail)"))
            }
            guard let root = JSON.parse(bodyString) else {
                return .failure(IllegalStateError("配对返回无效"))
            }
            let token = optString(root, key: "device_token").trimmingCharacters(in: .whitespacesAndNewlines)
            let userId = optString(root, key: "user_id").trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty || userId.isEmpty {
                return .failure(IllegalStateError("配对返回无效"))
            }
            return .success(FlowStudyPairResponse(deviceToken: token, userId: userId))
        } catch {
            return .failure(error)
        }
    }

    func pushSessions(serverUrl: String, deviceToken: String, deviceId: String, payloadJson: String) async -> Result<FlowStudyPushResponse, Error> {
        let baseUrl = normalizeServerUrl(serverUrl)
        if baseUrl.isEmpty { return .failure(ArgumentError("FlowStudy 地址为空")) }
        if deviceToken.isEmpty { return .failure(ArgumentError("设备 token 为空，请先配对")) }
        if payloadJson.isEmpty { return .failure(ArgumentError("payload 为空")) }

        do {
            let url = URL(string: "\(baseUrl)/api/artiflow/push-sessions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
            guard let payloadObject = JSON.parse(payloadJson) else {
                return .failure(ArgumentError("payload 解析失败"))
            }
            let body: [String: Any] = ["device_id": deviceId, "payload": payloadObject]
            request.httpBody = JSON.data(body)
            let (data, response) = try await transport.send(request)
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            guard response.statusCode >= 200 && response.statusCode < 300 else {
                let detail = parseErrorDetail(bodyString)
                return .failure(IllegalStateError("上传失败 (\(response.statusCode)): \(detail)"))
            }
            guard let root = JSON.parse(bodyString) else {
                return .failure(IllegalStateError("上传返回无效"))
            }
            return .success(FlowStudyPushResponse(
                insertedSessions: optInt(root, key: "inserted_sessions"),
                updatedSessions: optInt(root, key: "updated_sessions"),
                skippedSessions: optInt(root, key: "skipped_sessions"),
                importBatchId: optString(root, key: "import_batch_id").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        } catch {
            return .failure(error)
        }
    }

    private func normalizeServerUrl(_ value: String) -> String {
        return value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func defaultDeviceName() -> String {
        let name = UIDeviceCompatibility.name()
        return String(name.prefix(64)).isEmpty ? "iOS" : String(name.prefix(64))
    }

    private func parseErrorDetail(_ responseBody: String) -> String {
        let fallback = responseBody.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { "空响应" }
        if let root = JSON.parse(responseBody) {
            let detail = optString(root, key: "detail").ifBlank { optString(root, key: "message") }
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(trimmed.prefix(280)) }
        }
        return String(fallback.prefix(280))
    }
}

// MARK: - OpenSpeech ASR client (data/OpenSpeechAsrClient.kt)

func parseOpenSpeechTranscript(_ body: String) -> String {
    if body.isEmpty { return "" }
    guard let root = JSON.parse(body) else { return "" }
    guard let result = optObjectAny(root, key: "result") else { return "" }
    let text = optString(result, key: "text")
    if !text.isEmpty { return text }
    if let utterances = optArray(result, key: "utterances"), !utterances.isEmpty {
        var segments: [String] = []
        for item in utterances {
            let segment = optString(item, key: "text").trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty { segments.append(segment) }
        }
        return segments.joined(separator: "\n")
    }
    return ""
}

final class OpenSpeechAsrClient {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.shared) {
        self.transport = transport
    }

    func isConfigured(_ config: OpenSpeechRuntimeConfig = OpenSpeechRuntimeConfig(apiKey: "", resourceId: "", submitUrl: "", queryUrl: "", uid: "")) -> Bool {
        return !config.apiKey.isEmpty && !config.resourceId.isEmpty
    }

    func transcribeByAudioData(_ audioBytes: Data, config: OpenSpeechRuntimeConfig) async -> Result<String, Error> {
        if !isConfigured(config) {
            return .failure(IllegalStateError("请先在设置中配置 OpenSpeech 参数"))
        }
        if audioBytes.isEmpty {
            return .failure(ArgumentError("音频数据为空"))
        }
        let requestId = UUID().uuidString
        let audioBase64 = audioBytes.base64EncodedString()
        do {
            try await submitTask(requestId: requestId, audioBase64: audioBase64, config: config)
            let transcript = try await awaitTranscript(requestId: requestId, config: config)
            if transcript.isEmpty {
                return .failure(IllegalStateError("语音识别结果为空"))
            }
            return .success(transcript)
        } catch {
            return .failure(error)
        }
    }

    private func submitTask(requestId: String, audioBase64: String, config: OpenSpeechRuntimeConfig) async throws {
        let url = URL(string: config.submitUrl)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(config.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestId, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        let body: [String: Any] = [
            "user": ["uid": defaultUid(config)],
            "audio": [
                "data": audioBase64, "format": "wav", "codec": "raw",
                "rate": 16000, "bits": 16, "channel": 1
            ],
            "request": [
                "model_name": "bigmodel", "enable_itn": true, "enable_punc": false,
                "enable_ddc": false, "enable_speaker_info": false,
                "enable_channel_split": false, "show_utterances": false,
                "vad_segment": false, "sensitive_words_filter": ""
            ]
        ]
        request.httpBody = JSON.data(body)
        let (_, response) = try await transport.send(request)
        guard response.statusCode >= 200 && response.statusCode < 300 else {
            throw IllegalStateError("提交语音识别任务失败(\(response.statusCode)): HTTP 错误")
        }
    }

    private func awaitTranscript(requestId: String, config: OpenSpeechRuntimeConfig) async throws -> String {
        let pollAttempts = 24
        for attempt in 0..<pollAttempts {
            let query = try await queryTask(requestId: requestId, config: config)
            switch query.statusCode {
            case "20000000":
                if query.transcript.isEmpty {
                    throw IllegalStateError("语音识别结果为空")
                }
                return query.transcript
            case "20000001", "20000002":
                if attempt == pollAttempts - 1 {
                    throw IllegalStateError("语音识别超时，请稍后重试")
                }
                try await Task.sleep(nanoseconds: 1_500_000_000)
            default:
                let err = query.message.isEmpty ? "状态码 \(query.statusCode)" : query.message
                throw IllegalStateError("语音识别失败: \(err)")
            }
        }
        throw IllegalStateError("语音识别失败：未知状态")
    }

    private struct QueryResult {
        let statusCode: String
        let message: String
        let transcript: String
    }

    private func queryTask(requestId: String, config: OpenSpeechRuntimeConfig) async throws -> QueryResult {
        let url = URL(string: config.queryUrl)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(config.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestId, forHTTPHeaderField: "X-Api-Request-Id")
        request.httpBody = "{}".data(using: .utf8)
        let (data, response) = try await transport.send(request)
        let statusCode = (response.value(forHTTPHeaderField: "X-Api-Status-Code")) ?? ""
        let message = response.value(forHTTPHeaderField: "X-Api-Message") ?? ""
        if response.statusCode < 200 || response.statusCode >= 300 {
            return QueryResult(
                statusCode: statusCode.isEmpty ? String(response.statusCode) : statusCode,
                message: message.isEmpty ? "HTTP 错误" : message,
                transcript: ""
            )
        }
        let transcript = parseOpenSpeechTranscript(String(data: data, encoding: .utf8) ?? "")
        return QueryResult(
            statusCode: statusCode.isEmpty ? "20000000" : statusCode,
            message: message,
            transcript: transcript
        )
    }

    private func defaultUid(_ config: OpenSpeechRuntimeConfig) -> String {
        let trimmed = config.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "study-suit-user" : trimmed
    }
}

// MARK: - Mistake analyzer (data/MistakeAnalyzer.kt)

struct MistakeAnalysisResult {
    let errorType: String
    let knowledgePoints: [String]
    let explanation: String
    let suggestions: [String]
    let relatedTopics: [String]
}

struct MistakeAnalyzerConfig {
    var apiKey: String = ""
    var model: String = "gpt-4"
    var baseUrl: String = "http://49.235.88.239:3000/v1"
    var timeoutSeconds: Int = 60
}

final class MistakeAnalyzer {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.shared) {
        self.transport = transport
    }

    func analyzeMistake(question: String, studentAnswer: String, correctAnswer: String, subject: String, config: MistakeAnalyzerConfig = MistakeAnalyzerConfig()) async -> Result<MistakeAnalysisResult, Error> {
        if question.isEmpty { return .failure(ArgumentError("题目不能为空")) }
        if studentAnswer.isEmpty { return .failure(ArgumentError("学生答案不能为空")) }
        if correctAnswer.isEmpty { return .failure(ArgumentError("标准答案不能为空")) }
        if config.apiKey.isEmpty { return .failure(IllegalStateError("请先配置 API Key")) }

        do {
            let systemPrompt = buildSystemPrompt(subject: subject)
            let userPrompt = buildUserPrompt(question: question, studentAnswer: studentAnswer, correctAnswer: correctAnswer)
            let body = JSON.string([
                "model": config.model,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ],
                "temperature": 0.7
            ])
            let url = URL(string: "\(config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = body.data(using: .utf8)
            request.timeoutInterval = TimeInterval(config.timeoutSeconds)
            let (data, response) = try await transport.send(request)
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            guard response.statusCode >= 200 && response.statusCode < 300 else {
                let message = extractErrorMessage(bodyString)
                return .failure(IllegalStateError("AI 分析请求失败 (\(response.statusCode)): \(message)"))
            }
            let text = parseAssistantText(bodyString)
            if text.isEmpty {
                return .failure(IllegalStateError("AI 分析返回为空，请稍后重试"))
            }
            return .success(parseAnalysisResult(text))
        } catch {
            return .failure(error)
        }
    }

    private func buildSystemPrompt(subject: String) -> String {
        return """
        你是一名专业的\(subject)教师，擅长分析学生的答题错误。
        请分析学生答案与标准答案的差异，找出：
        1. 错误类型（计算错误、概念错误、审题错误、方法错误等）
        2. 涉及的知识点
        3. 错误原因的详细解释
        4. 针对性的改进建议
        5. 需要巩固的相关知识点

        请以 JSON 格式返回结果，格式如下：
        ```json
        {
          "errorType": "错误类型",
          "knowledgePoints": ["知识点1", "知识点2"],
          "explanation": "详细错误解析",
          "suggestions": ["建议1", "建议2"],
          "relatedTopics": ["相关知识点1", "相关知识点2"]
        }
        ```
        """
    }

    private func buildUserPrompt(question: String, studentAnswer: String, correctAnswer: String) -> String {
        return """
        请分析以下答题错误：

        【题目】
        \(question)

        【学生答案】
        \(studentAnswer)

        【标准答案】
        \(correctAnswer)

        请分析学生的错误原因并提供改进建议。
        """
    }

    private func parseAssistantText(_ body: String) -> String {
        guard let root = JSON.parse(body) else { return "" }
        if let choices = optArray(root, key: "choices"), !choices.isEmpty {
            if let message = optObjectAny(choices[0], key: "message") {
                let content = optString(message, key: "content")
                if !content.isEmpty { return content }
            }
        }
        return ""
    }

    private func parseAnalysisResult(_ text: String) -> MistakeAnalysisResult {
        let jsonText = extractJsonFromMarkdown(text) ?? text
        guard let root = JSON.parse(jsonText) else {
            return MistakeAnalysisResult(errorType: "分析结果解析失败", knowledgePoints: [], explanation: text, suggestions: [], relatedTopics: [])
        }
        let errorType = optString(root, key: "errorType").ifBlank { "未知错误类型" }
        let knowledgePoints = (optArray(root, key: "knowledgePoints") ?? []).map { optString($0) }.filter { !$0.isEmpty }
        let explanation = optString(root, key: "explanation").ifBlank { text }
        let suggestions = (optArray(root, key: "suggestions") ?? []).map { optString($0) }.filter { !$0.isEmpty }
        let relatedTopics = (optArray(root, key: "relatedTopics") ?? []).map { optString($0) }.filter { !$0.isEmpty }
        return MistakeAnalysisResult(errorType: errorType, knowledgePoints: knowledgePoints, explanation: explanation, suggestions: suggestions, relatedTopics: relatedTopics)
    }

    private func extractJsonFromMarkdown(_ text: String) -> String? {
        let regex = makeRegex("```(?:json)?\\s*([\\s\\S]*?)\\s*```")
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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

// MARK: - Mistake exporter (data/MistakeExporter.kt)

enum MistakeExporter {
    static func toMarkdown(_ mistakes: [MistakeQuestion]) -> String {
        if mistakes.isEmpty { return "暂无错题可导出。" }
        var output = "# 错题本导出\n\n"
        output += "- 导出时间：\(formatTimestamp(currentTimeMillis(), format: "yyyy-MM-dd HH:mm"))\n"
        output += "- 错题数量：\(mistakes.count)\n"
        for (index, mistake) in mistakes.enumerated() {
            output += "\n## 第\(index + 1)题\n"
            output += "- 科目：\(mistake.subject)\n"
            output += "- 题型：\(mistake.questionType)\n"
            output += "- 错误类型：\(mistake.mistakeType.rawValue)\n"
            output += "- 知识点：\(mistake.knowledgePoints.joined(separator: "、"))\n"
            output += "\n**题干**\n\(mistake.questionText)\n"
            output += "\n**正确答案**\n\(mistake.correctAnswer)\n"
            output += "\n**学生答案**\n\(mistake.studentAnswer)\n"
            if let analysis = mistake.aiAnalysis {
                output += "\n**AI 分析**\n"
                output += "- 根本原因：\(analysis.rootCause)\n"
                output += "- 改进建议：\(analysis.suggestions.joined(separator: "；"))\n"
                output += "- 相关概念：\(analysis.relatedConcepts.joined(separator: "、"))\n"
            }
        }
        return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    static func toJson(_ mistakes: [MistakeQuestion]) -> String {
        let array = mistakes.map { mistake -> [String: Any] in
            var json: [String: Any] = [
                "id": mistake.id,
                "questionText": mistake.questionText,
                "subject": mistake.subject,
                "questionType": mistake.questionType,
                "mistakeType": mistake.mistakeType.rawValue,
                "knowledgePoints": mistake.knowledgePoints,
                "correctAnswer": mistake.correctAnswer,
                "studentAnswer": mistake.studentAnswer,
                "mistakeReason": mistake.mistakeReason,
                "createdAt": mistake.createdAt,
                "masteryLevel": mistake.masteryLevel,
                "reviewCount": mistake.reviewCount
            ]
            if let image = mistake.questionImage { json["questionImage"] = image }
            if let reviewedAt = mistake.reviewedAt { json["reviewedAt"] = reviewedAt }
            if let nextReviewAt = mistake.nextReviewAt { json["nextReviewAt"] = nextReviewAt }
            if let analysis = mistake.aiAnalysis {
                json["aiAnalysis"] = [
                    "rootCause": analysis.rootCause,
                    "suggestions": analysis.suggestions,
                    "relatedConcepts": analysis.relatedConcepts
                ]
            }
            return json
        }
        return JSON.string(array)
    }
}

// MARK: - Image MIME detection (ui/StudyChatMediaUtils.kt)

func detectImageMimeType(_ rawBytes: Data, fallback: String = "image/jpeg") -> String {
    guard rawBytes.count >= 12 else { return fallback }
    if rawBytes.matchesSignature([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
    if rawBytes.matchesSignature([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
    if rawBytes.matchesSignature([0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
    if rawBytes.matchesSignature([0x42, 0x4D]) { return "image/bmp" }
    if rawBytes.matchesAscii("RIFF") && rawBytes.matchesAscii("WEBP", offset: 8) { return "image/webp" }
    if rawBytes.matchesAscii("ftyp", offset: 4) {
        switch rawBytes.readAscii(8, 4) {
        case "heic", "heix", "hevc", "hevx", "heim", "heis": return "image/heic"
        case "mif1", "msf1": return "image/heif"
        case "avif", "avis": return "image/avif"
        default: return fallback
        }
    }
    return fallback
}

func toImagePayloads(_ imageBytesList: [Data]) -> [ImagePayload] {
    return imageBytesList
        .filter { !$0.isEmpty }
        .map { ImagePayload(bytes: $0, mimeType: detectImageMimeType($0)) }
}

private extension Data {
    func matchesSignature(_ signature: [UInt8], offset: Int = 0) -> Bool {
        guard count >= offset + signature.count else { return false }
        for (index, byte) in signature.enumerated() {
            if self[offset + index] != byte { return false }
        }
        return true
    }

    func matchesAscii(_ value: String, offset: Int = 0) -> Bool {
        let bytes = Array(value.utf8)
        guard count >= offset + bytes.count else { return false }
        for (index, byte) in bytes.enumerated() {
            if self[offset + index] != byte { return false }
        }
        return true
    }

    func readAscii(_ offset: Int, _ length: Int) -> String {
        guard count >= offset + length else { return "" }
        return String(data: subdata(in: offset..<(offset + length)), encoding: .ascii) ?? ""
    }
}

// MARK: - Shared helpers

private func makeRegex(_ pattern: String) -> NSRegularExpression {
    // swiftlint:disable:next force_try
    return try! NSRegularExpression(pattern: pattern, options: [])
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        return isEmpty ? fallback : self
    }
}

enum UIDeviceCompatibility {
    static func name() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "iOS"
        #endif
    }
}
