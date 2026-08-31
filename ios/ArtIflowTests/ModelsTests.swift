import XCTest
@testable import ArtIflow

final class ModelsTests: XCTestCase {
    private func assistantMessage(spans: [SpanData], mainSpan: SpanData? = nil, id: String = "msg-2") -> ChatMessage {
        return .assistant(id: id, time: "10:01", spans: spans, mainSpan: mainSpan)
    }

    func testFindSpanByIdReturnsMatchingAssistantSpan() {
        let messages: [ChatMessage] = [
            .user(id: "msg-1", time: "10:00", text: "question"),
            assistantMessage(spans: [
                SpanData(id: "span-1", content: "第一段", sourceQuestion: "q1"),
                SpanData(id: "span-2", content: "第二段", sourceQuestion: "q1")
            ])
        ]
        let found = findSpanById(messages, spanId: "span-2")
        XCTAssertEqual(found?.id, "span-2")
        XCTAssertEqual(found?.content, "第二段")
    }

    func testFindSpanByIdReturnsNullForMissingSpan() {
        let messages: [ChatMessage] = [
            assistantMessage(spans: [SpanData(id: "span-1", content: "第一段", sourceQuestion: "q1")])
        ]
        XCTAssertNil(findSpanById(messages, spanId: "missing"))
    }

    func testFindSpanByIdReturnsMainSpanWhenRequested() {
        let messages: [ChatMessage] = [
            assistantMessage(spans: [SpanData(id: "span-1", content: "第一段", sourceQuestion: "q1")], mainSpan: SpanData(id: "span-main", content: "整题回答", sourceQuestion: "q1"))
        ]
        let found = findSpanById(messages, spanId: "span-main")
        XCTAssertEqual(found?.id, "span-main")
        XCTAssertEqual(found?.content, "整题回答")
    }

    func testFindLatestAssistantSpanReturnsLastSpanFromLatestAssistant() {
        let messages: [ChatMessage] = [
            assistantMessage(spans: [SpanData(id: "span-1", content: "第一段", sourceQuestion: "q1")], id: "msg-1"),
            .user(id: "msg-2", time: "10:01", text: "继续"),
            assistantMessage(spans: [
                SpanData(id: "span-2", content: "第二段", sourceQuestion: "q2"),
                SpanData(id: "span-3", content: "第三段", sourceQuestion: "q2")
            ], id: "msg-3")
        ]
        XCTAssertEqual(findLatestAssistantSpan(messages)?.id, "span-3")
    }

    func testFindLatestAssistantQuestionSpanPrefersMainSpan() {
        let messages: [ChatMessage] = [
            assistantMessage(spans: [SpanData(id: "span-1", content: "第一段", sourceQuestion: "q1")], id: "msg-1"),
            assistantMessage(spans: [SpanData(id: "span-2", content: "第二段", sourceQuestion: "q2")], mainSpan: SpanData(id: "span-main-2", content: "第二题整题回答", sourceQuestion: "q2"), id: "msg-2")
        ]
        XCTAssertEqual(findLatestAssistantQuestionSpan(messages)?.id, "span-main-2")
    }

    func testFindDetailByIdReturnsMatchingDetail() {
        let details = [
            SpanDetail(id: "detail-1", mode: "自动讲解", time: "10:00", question: nil, answer: "a1", parentDetailId: nil, summary: nil),
            SpanDetail(id: "detail-2", mode: "精细追问", time: "10:01", question: "q2", answer: "a2", parentDetailId: nil, summary: nil)
        ]
        let found = findDetailById(details, detailId: "detail-2")
        XCTAssertEqual(found?.id, "detail-2")
        XCTAssertEqual(found?.question, "q2")
    }

    func testBuildDetailPathReturnsRootToTargetPath() {
        let details = [
            SpanDetail(id: "detail-3", mode: "精细追问", time: "10:02", question: "q3", answer: "a3", parentDetailId: "detail-2", summary: nil),
            SpanDetail(id: "detail-2", mode: "精细追问", time: "10:01", question: "q2", answer: "a2", parentDetailId: "detail-1", summary: nil),
            SpanDetail(id: "detail-1", mode: "自动讲解", time: "10:00", question: nil, answer: "a1", parentDetailId: nil, summary: nil)
        ]
        let path = buildDetailPath(details, detailId: "detail-3")
        XCTAssertEqual(path.map { $0.id }, ["detail-1", "detail-2", "detail-3"])
    }

    func testUpdateWithIncrementsTopicAndBehaviorCounters() {
        let profile = ProfileState(level: "高二")
        let updated = profile.updateWith(text: "函数最值题怎么做", isFollowup: true, isVoice: true)
        XCTAssertEqual(updated.followups, 1)
        XCTAssertEqual(updated.voiceFollowups, 1)
        XCTAssertEqual(updated.topicHits["函数"], 1)
    }

    func testDetectTopicsForProfileReturnsFallbackForUnknownText() {
        XCTAssertEqual(detectTopicsForProfile("今天状态不错"), ["通用方法"])
    }

    func testNormalizeImagePromptReplacesLegacyOrBlankPrompt() {
        let legacyPrompt = "你是一名中学学科辅导老师。请先识别图片中的题干，再按步骤讲解并给出最终答案。如果图片里有多个小题，请按小题编号分别作答。输出格式：\n1) 题目识别\n2) 解题思路\n3) 详细步骤\n4) 最终答案"
        XCTAssertTrue(normalizeImagePrompt("  ").contains("请识别题目并简洁作答"))
        XCTAssertTrue(normalizeImagePrompt(legacyPrompt).contains("请识别题目并简洁作答"))
        XCTAssertEqual(normalizeImagePrompt("按步骤给出关键点"), "按步骤给出关键点")
    }

    func testToArkRuntimeConfigNormalizesLegacySystemPrompt() {
        var settings = RuntimeSettings.defaults()
        settings.arkApiKey = "key"
        settings.arkModel = "model"
        settings.arkBaseUrl = "https://example.com"
        settings.arkEndpoint = "responses"
        settings.arkSystemPrompt = "你是一个有用的AI学习辅导助手，擅长把复杂知识点讲清楚，优先给步骤化解释。"
        let config = settings.toArkRuntimeConfig()
        XCTAssertEqual(config.apiKey, "key")
        XCTAssertTrue(config.systemPrompt.contains("先给结论"))
    }

    func testSaveCurrentModelPresetStoresAndReappliesCustomModel() {
        var base = RuntimeSettings.defaults()
        base.customModelBaseUrl = "https://api.openai.com/v1"
        base.customModelApiKey = "secret-key"
        base.customModelName = "gpt-4o-mini"
        let saved = base.saveCurrentModelPreset("OpenAI 日常")
        let preset = saved.customModelPresets.first!
        let restored = saved.clearCustomModel().applyModelPreset(preset)
        XCTAssertEqual(saved.customModelPresets.count, 1)
        XCTAssertTrue(saved.hasCompleteCustomModel())
        XCTAssertEqual(preset.name, "OpenAI 日常")
        XCTAssertEqual(restored.customModelBaseUrl, "https://api.openai.com/v1")
        XCTAssertEqual(restored.customModelApiKey, "secret-key")
        XCTAssertEqual(restored.customModelName, "gpt-4o-mini")
    }

    func testToArkRuntimeConfigPrefersCustomModelWhenThreeFieldsProvided() {
        var settings = RuntimeSettings.defaults()
        settings.customModelBaseUrl = "https://api.openai.com/v1"
        settings.customModelApiKey = "custom-key"
        settings.customModelName = "gpt-4o-mini"
        let config = settings.toArkRuntimeConfig()
        XCTAssertEqual(config.apiKey, "custom-key")
        XCTAssertEqual(config.model, "gpt-4o-mini")
        XCTAssertEqual(config.baseUrl, "https://api.openai.com/v1")
        XCTAssertEqual(config.endpoint, "chat/completions")
    }

    // buildDetailPath：根 → 中间 → 叶 的分层链路回溯
    func testBuildDetailPathWalksParentChainRootToLeaf() {
        let root = SpanDetail(id: "d1", mode: "精细追问", time: "10:00", question: "根追问", answer: "a1", parentDetailId: nil, summary: nil)
        let mid = SpanDetail(id: "d2", mode: "精细追问", time: "10:01", question: "中间", answer: "a2", parentDetailId: "d1", summary: nil)
        let leaf = SpanDetail(id: "d3", mode: "精细追问", time: "10:02", question: "叶子", answer: "a3", parentDetailId: "d2", summary: nil)
        let details = [root, mid, leaf]

        XCTAssertEqual(buildDetailPath(details: details, detailId: "d3").map { $0.id }, ["d1", "d2", "d3"])
        XCTAssertEqual(buildDetailPath(details: details, detailId: "d2").map { $0.id }, ["d1", "d2"])
        XCTAssertEqual(buildDetailPath(details: details, detailId: "d1").map { $0.id }, ["d1"])
        // 缺失或孤立 detail 不应死循环
        XCTAssertEqual(buildDetailPath(details: details, detailId: "missing"), [])
    }
}
