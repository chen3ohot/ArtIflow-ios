import XCTest
@testable import ArtIflow

final class StateReducersTests: XCTestCase {
    private func makeState(input: String = "", messages: [ChatMessage] = [], settings: RuntimeSettings? = nil) -> ChatUiState {
        let s = settings ?? RuntimeSettings.defaults()
        // 成员式初始化需按声明顺序传参：messages 在 input 之前
        return ChatUiState(messages: messages, input: input, settings: s, settingsDraft: s)
    }

    func testQueueImageQuestionStateAppendsMessageAndUpdatesProfile() {
        let base = makeState(input: "before")
        let userMessage = ChatMessage.user(id: "msg-1", time: "10:00", text: "拍照问题")
        let updated = queueImageQuestionState(current: base, userMessage: userMessage, question: "函数题怎么做", source: "拍照搜题")
        XCTAssertEqual(updated.messages.count, 1)
        XCTAssertEqual(updated.messages.first?.id, "msg-1")
        XCTAssertFalse(updated.knowledgePoints.isEmpty)
        XCTAssertEqual(updated.profile.followups, 0)
    }

    func testQueueQuestionStateHandlesInputAndFollowupFlags() {
        let base = makeState(input: "原输入")
        let userMessage = ChatMessage.user(id: "msg-2", time: "10:01", text: "追问")
        let updated = queueQuestionState(current: base, userMessage: userMessage, question: "导数最值怎么求", isFollowup: true, isVoice: false, clearInput: true)
        XCTAssertEqual(updated.input, "")
        XCTAssertEqual(updated.messages.count, 1)
        XCTAssertEqual(updated.profile.followups, 1)
        XCTAssertEqual(updated.profile.voiceFollowups, 0)
    }

    func testQueueSpanFollowupStateMarksProcessingAndVoiceCounters() {
        let base = makeState(input: "待发送输入")
        let updated = queueSpanFollowupState(current: base, spanId: "span-9", question: "这个力学题为什么这么列式", isVoice: true, clearInput: true)
        XCTAssertEqual(updated.input, "")
        XCTAssertTrue(updated.processingSpanIds.contains("span-9"))
        XCTAssertEqual(updated.profile.followups, 1)
        XCTAssertEqual(updated.profile.voiceFollowups, 1)
    }

    func testAppendAssistantMessageStateAppendsMessageAndToast() {
        let base = makeState(messages: [.user(id: "msg-1", time: "10:00", text: "问题")])
        let assistant = ChatMessage.assistant(id: "msg-2", time: "10:01", spans: [SpanData(id: "span-1", content: "答案", sourceQuestion: "问题")])
        let updated = appendAssistantMessageState(current: base, assistantMessage: assistant, toastMessage: "完成", knowledgeTexts: ["导数与最值"])
        XCTAssertEqual(updated.messages.count, 2)
        XCTAssertEqual(updated.toastMessage, "完成")
        XCTAssertFalse(updated.knowledgePoints.isEmpty)
    }

    func testUpsertAssistantMessageStateReplacesMessageWithSameId() {
        let base = makeState(messages: [
            .user(id: "msg-1", time: "10:00", text: "问题"),
            .assistant(id: "msg-2", time: "10:01", spans: [SpanData(id: "span-1", content: "旧内容", sourceQuestion: "问题")])
        ])
        let updatedAssistant = ChatMessage.assistant(id: "msg-2", time: "10:01", spans: [SpanData(id: "span-2", content: "新内容", sourceQuestion: "问题")])
        let updated = upsertAssistantMessageState(current: base, assistantMessage: updatedAssistant)
        XCTAssertEqual(updated.messages.count, 2)
        if case .assistant(_, _, let spans, _, _) = updated.messages[1] {
            XCTAssertEqual(spans.first?.content, "新内容")
        } else {
            XCTFail("expected assistant")
        }
    }

    func testRollbackQueuedUserMessageStateRemovesFailedMessageAndRestoresInputWhenEmpty() {
        let base = makeState(input: "", messages: [
            .user(id: "msg-1", time: "10:00", text: "上一条"),
            .assistant(id: "msg-2", time: "10:01", spans: [SpanData(id: "span-1", content: "上一条回答", sourceQuestion: "上一条")]),
            .user(id: "msg-3", time: "10:02", text: "这条超时")
        ])
        let updated = rollbackQueuedUserMessageState(current: base, messageId: "msg-3", restoredInput: "这条超时", toastMessage: "回答失败：timeout")
        XCTAssertEqual(updated.messages.count, 2)
        XCTAssertTrue(updated.messages.allSatisfy { $0.id != "msg-3" })
        XCTAssertEqual(updated.input, "这条超时")
        XCTAssertEqual(updated.toastMessage, "回答失败：timeout")
    }

    func testRollbackQueuedUserMessageStateDoesNotOverrideExistingInput() {
        let base = makeState(input: "正在输入新问题", messages: [.user(id: "msg-1", time: "10:00", text: "超时问题")])
        let updated = rollbackQueuedUserMessageState(current: base, messageId: "msg-1", restoredInput: "超时问题")
        XCTAssertEqual(updated.input, "正在输入新问题")
        XCTAssertTrue(updated.messages.isEmpty)
    }
}
