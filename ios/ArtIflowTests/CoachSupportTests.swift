import XCTest
@testable import ArtIflow

final class CoachSupportTests: XCTestCase {
    func testDailyDigestReturnsFallbackWhenNoSamples() {
        let digest = buildCoachDailyDigest(messages: [], histories: [:], savedQuestions: [], knowledgePoints: [:], nowMillis: 1)
        XCTAssertTrue(digest.headline.contains("先给我几道题"))
        XCTAssertTrue(digest.summary.contains("足够样本"))
        XCTAssertFalse(digest.recommendedQuestions.isEmpty)
    }

    func testDailyDigestSurfacesFocusAreaAndRecommendation() {
        let question = "这道函数图像题我不会，为什么这里要这样判断？"
        let messages: [ChatMessage] = [
            .user(id: "msg-1", time: "10:00", text: question),
            .assistant(id: "msg-2", time: "10:01",
                spans: [SpanData(id: "span-1", content: "先看函数单调性，再判断图像变化。", sourceQuestion: question)],
                mainSpan: SpanData(id: "span-main-1", content: "先看函数单调性，再判断图像变化。", sourceQuestion: question))
        ]
        let savedQuestions = [
            SavedQuestion(id: "saved-1", sourceMessageId: "msg-2", question: "已知二次函数图像，判断最值和单调区间", answer: "先找对称轴，再判断开口方向。", sourceTime: "10:01", savedAt: 100, followupCount: 2, knowledgeTags: ["函数与图像"])
        ]
        let digest = buildCoachDailyDigest(messages: messages, histories: [:], savedQuestions: savedQuestions, knowledgePoints: ["函数与图像": 2], nowMillis: 1000)
        XCTAssertTrue(digest.focusAreas.contains { $0.point == "函数与图像" })
        XCTAssertTrue(digest.recommendedQuestions.contains { $0.prompt.contains("函数与图像") })
    }

    func testTrainingRoundsFillsToThreeRounds() {
        let digest = CoachDailyDigest(
            dateKey: "2026-03-07", generatedAt: 1000,
            headline: "今天先盯住函数与图像", summary: "你更容易卡在切入点判断。",
            focusAreas: [
                CoachFocusArea(point: "函数与图像", level: .high, diagnosis: "基础判断不稳", action: "先判断图像特征再列步骤", evidence: "经常问为什么这样判断")
            ],
            recommendedQuestions: [
                CoachRecommendedQuestion(id: "rec-1", title: "函数题", reason: "先补基础判断。", prompt: "请给我一道函数与图像的典型题。", basis: "", anchorSavedQuestionId: nil)
            ]
        )
        let rounds = buildCoachTrainingRounds(digest)
        XCTAssertEqual(rounds.count, 3)
        XCTAssertTrue(rounds.first!.prompt.contains("函数与图像"))
    }

    func testTrainingPromptPrefersFirstRecommendedQuestion() {
        let digest = CoachDailyDigest(
            dateKey: "2026-03-07", generatedAt: 1000,
            headline: "今天先盯住函数与图像", summary: "你更容易卡在切入点判断。",
            focusAreas: [], recommendedQuestions: [
                CoachRecommendedQuestion(id: "rec-1", title: "函数题", reason: "先补基础判断。", prompt: "请给我一道函数与图像的典型题。", basis: "", anchorSavedQuestionId: nil)
            ]
        )
        XCTAssertEqual(buildCoachTrainingPrompt(digest), "请给我一道函数与图像的典型题。")
    }

    func testTrainingEvaluationPromptContainsQuestionAndAnswer() {
        let round = CoachRecommendedQuestion(id: "rec-1", title: "函数与图像 · 典型题", reason: "先补基础判断。", prompt: "请给我一道函数与图像的典型题。", basis: "", anchorSavedQuestionId: nil)
        let prompt = buildTrainingEvaluationPrompt(round: round, trainingQuestion: "已知函数图像，判断单调区间。", studentAnswer: "我觉得先看开口方向。")
        XCTAssertTrue(prompt.contains("已知函数图像"))
        XCTAssertTrue(prompt.contains("我觉得先看开口方向"))
        XCTAssertTrue(prompt.contains("可以进入下一题"))
    }

    func testQuickActionsIncludeFocusAndRecommendationShortcuts() {
        let digest = CoachDailyDigest(
            dateKey: "2026-03-07", generatedAt: 1000,
            headline: "今天先盯住函数与图像", summary: "你更容易卡在切入点判断。",
            focusAreas: [
                CoachFocusArea(point: "函数与图像", level: .high, diagnosis: "基础判断不稳", action: "先看图像特征", evidence: "经常卡在切入点")
            ],
            recommendedQuestions: [
                CoachRecommendedQuestion(id: "rec-1", title: "函数与图像 · 典型题", reason: "先补切入点判断。", prompt: "请给我一道函数与图像的典型题。", basis: "", anchorSavedQuestionId: nil)
            ]
        )
        let actions = buildCoachQuickActions(digest)
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(actions.contains { $0.label.contains("核心问题") })
        XCTAssertTrue(actions.contains { $0.prompt.contains("函数与图像") })
        XCTAssertTrue(actions.contains { $0.label.contains("练前") })
    }

    func testReplyQuickActionsReturnTrainingHintsWhenAwaitingAnswer() {
        let actions = buildCoachReplyQuickActions(
            message: CoachChatMessage(id: "msg-1", role: .assistant, time: "10:00", text: "这是一道训练题"),
            digest: CoachDailyDigest(dateKey: "2026-03-07", generatedAt: 1, headline: "今天先盯住函数与图像", summary: "先补函数与图像", focusAreas: [], recommendedQuestions: []),
            training: DailyTrainingState(
                dateKey: "2026-03-07",
                rounds: [CoachRecommendedQuestion(id: "rec-1", title: "函数与图像 · 典型题", reason: "先补基础判断", prompt: "请给我一道函数题", basis: "", anchorSavedQuestionId: nil)],
                currentIndex: 0, phase: .awaitingAnswer, currentQuestionText: "题目"
            )
        )
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(actions.contains { $0.label.contains("提示") })
        XCTAssertTrue(actions.contains { $0.prompt.contains("第一步") })
    }

    func testReplyQuickActionsReturnFollowupPromptsForGeneralCoachReply() {
        let actions = buildCoachReplyQuickActions(
            message: CoachChatMessage(id: "msg-1", role: .assistant, time: "10:00", text: "你主要漏了函数与图像的判断依据。"),
            digest: CoachDailyDigest(
                dateKey: "2026-03-07", generatedAt: 1,
                headline: "今天先盯住函数与图像", summary: "先补函数与图像",
                focusAreas: [CoachFocusArea(point: "函数与图像", level: .high, diagnosis: "判断依据不稳", action: "先看图像特征", evidence: "经常问为什么")],
                recommendedQuestions: []
            ),
            training: DailyTrainingState()
        )
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(actions.contains { $0.label.contains("出一道题") })
        XCTAssertTrue(actions.contains { $0.prompt.contains("函数与图像") })
        XCTAssertTrue(actions.contains { $0.label.contains("具体") || $0.label.contains("其他") })
    }

    func testRecommendationFollowupPromptMentionsTitleAndReason() {
        let prompt = buildCoachRecommendationFollowupPrompt(
            CoachRecommendedQuestion(id: "rec-1", title: "函数与图像 · 典型题", reason: "先补切入点判断。", prompt: "请给我一道函数与图像的典型题。", basis: "", anchorSavedQuestionId: nil)
        )
        XCTAssertTrue(prompt.contains("函数与图像 · 典型题"))
        XCTAssertTrue(prompt.contains("先补切入点判断"))
        XCTAssertTrue(prompt.contains("第一眼先看什么"))
    }

    func testConversationTurnsGroupsByTurn() {
        let turns = buildCoachConversationTurns([
            CoachChatMessage(id: "u1", role: .user, time: "10:00", text: "第1问"),
            CoachChatMessage(id: "a1", role: .assistant, time: "10:01", text: "第1答"),
            CoachChatMessage(id: "u2", role: .user, time: "10:02", text: "第2问"),
            CoachChatMessage(id: "a2", role: .assistant, time: "10:03", text: "第2答")
        ])
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].messages.map { $0.id }, ["u1", "a1"])
        XCTAssertEqual(turns[1].messages.map { $0.id }, ["u2", "a2"])
    }

    func testConversationMessagesPrependsContextAndMapsRoles() {
        let digest = CoachDailyDigest(dateKey: "2026-03-07", generatedAt: 1000, headline: "今天先盯住函数与图像", summary: "你更容易卡在切入点判断。", focusAreas: [], recommendedQuestions: [])
        let coachMessages = [
            CoachChatMessage(id: "msg-1", role: .user, time: "10:00", text: "我到底漏了什么？"),
            CoachChatMessage(id: "msg-2", role: .assistant, time: "10:01", text: "你主要漏了判断依据。")
        ]
        let requestMessages = buildCoachConversationMessages(
            digest: digest, coachMessages: coachMessages, profile: ProfileState(level: "高二"),
            knowledgePoints: ["函数与图像": 3], knowledgeGapInsights: [], savedQuestions: []
        )
        XCTAssertFalse(requestMessages.isEmpty)
        XCTAssertEqual(requestMessages.first?.role, "user")
        XCTAssertTrue(requestMessages.first!.text.contains("今日教练总结"))
        let tail = Array(requestMessages.dropFirst())
        XCTAssertEqual(tail, [
            ArkRequestMessage(role: "user", text: "我到底漏了什么？"),
            ArkRequestMessage(role: "assistant", text: "你主要漏了判断依据。")
        ])
    }

    func testDailyDigestRecommendationCarriesBasisAndAnchorQuestion() {
        let savedQuestions = [
            SavedQuestion(id: "saved-anchor", sourceMessageId: "msg-2", question: "已知二次函数图像，判断最值和单调区间", answer: "先找对称轴，再判断开口方向。", sourceTime: "10:01", savedAt: 100, followupCount: 2, knowledgeTags: ["函数与图像"])
        ]
        let digest = buildCoachDailyDigest(
            messages: [
                .user(id: "msg-1", time: "10:00", text: "函数图像这题我总不会"),
                .assistant(id: "msg-2", time: "10:01",
                    spans: [SpanData(id: "span-1", content: "先看图像特征。", sourceQuestion: "函数图像这题我总不会")],
                    mainSpan: SpanData(id: "span-main", content: "先看图像特征。", sourceQuestion: "函数图像这题我总不会"))
            ],
            histories: [:], savedQuestions: savedQuestions, knowledgePoints: ["函数与图像": 3], nowMillis: 1000
        )
        let question = digest.recommendedQuestions.first!
        XCTAssertEqual(question.anchorSavedQuestionId, "saved-anchor")
        XCTAssertTrue(question.basis.contains("函数与图像"))
        XCTAssertTrue(question.basis.contains("依据题") || question.basis.contains("卡住"))
    }
}
