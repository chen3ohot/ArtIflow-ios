import XCTest
@testable import ArtIflow

final class ArkApiClientTests: XCTestCase {
    private func runtimeConfig(endpoint: String) -> ArkRuntimeConfig {
        return ArkRuntimeConfig(apiKey: "test-key", model: "test-model", baseUrl: "https://ark.example.com/api/v3", endpoint: endpoint, systemPrompt: "")
    }

    func testGenerateReplyResponsesEndpointParsesOutputText() async {
        let client = ArkApiClient(transport: StaticHTTPTransport(code: 200, body: #"{"output_text":"先给结论，再给要点。"}"#))
        let result = await client.generateReply(messages: [ArkRequestMessage(role: "user", text: "帮我讲一下函数最值")], config: runtimeConfig(endpoint: "responses"))
        switch result {
        case .success(let text): XCTAssertEqual(text, "先给结论，再给要点。")
        case .failure(let error): XCTFail("expected success: \(error)")
        }
    }

    func testGenerateReplyStreamResponsesEndpointAggregatesDeltaChunks() async {
        let streamPayload = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"先给结论\"}\n" +
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"，再给步骤\"}\n" +
            "data: [DONE]\n"
        var observed = ""
        let client = ArkApiClient(transport: StaticHTTPTransport(code: 200, body: streamPayload, contentType: "text/event-stream"))
        let result = await client.generateReplyStream(
            messages: [ArkRequestMessage(role: "user", text: "讲解这题")],
            config: runtimeConfig(endpoint: "responses"),
            onDelta: { delta in observed.append(delta) }
        )
        switch result {
        case .success(let text):
            XCTAssertEqual(observed, "先给结论，再给步骤")
            XCTAssertEqual(text, "先给结论，再给步骤")
        case .failure(let error):
            XCTFail("expected success: \(error)")
        }
    }

    func testGenerateReplyFailsWhenNotConfigured() async {
        let client = ArkApiClient(transport: StaticHTTPTransport(code: 200, body: "{}"))
        let config = ArkRuntimeConfig(apiKey: "", model: "m", baseUrl: "https://x", endpoint: "responses", systemPrompt: "")
        let result = await client.generateReply(messages: [ArkRequestMessage(role: "user", text: "q")], config: config)
        switch result {
        case .success: XCTFail("expected failure")
        case .failure: break
        }
    }

    // 兼容端点忽略 stream:true、直接返回普通 chat/completions JSON 时，
    // 流式解析应把整体 message.content 作为一次 delta 返回，而不是判为空。
    func testGenerateReplyStreamFallsBackToPlainJsonWhenNotSse() async {
        let body = #"{"choices":[{"index":0,"message":{"role":"assistant","content":"这是一段普通回答"}}]}"#
        var observed = ""
        let client = ArkApiClient(transport: StaticHTTPTransport(code: 200, body: body))
        let result = await client.generateReplyStream(
            messages: [ArkRequestMessage(role: "user", text: "讲解这题")],
            config: runtimeConfig(endpoint: "chat/completions"),
            onDelta: { delta in observed.append(delta) }
        )
        switch result {
        case .success(let text):
            XCTAssertEqual(text, "这是一段普通回答")
            XCTAssertEqual(observed, "这是一段普通回答")
        case .failure(let error):
            XCTFail("expected success: \(error)")
        }
    }
}
