import XCTest
@testable import ArtIflow

// 测试用错误类型：localizedDescription 直接返回传入消息，便于 resolveErrorHint 解析
struct RuntimeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class ViewModelSupportTests: XCTestCase {
    private func assistant(spans: [SpanData], mainSpan: SpanData? = nil, id: String = "msg-2") -> ChatMessage {
        return .assistant(id: id, time: "10:01", spans: spans, mainSpan: mainSpan)
    }

    func testToArkMessagesFiltersIntroAndBlankUserInput() {
        let messages: [ChatMessage] = [
            assistant(spans: [SpanData(id: "span-1", content: "引导", sourceQuestion: "初始化引导")], id: "msg-1"),
            .user(id: "msg-2", time: "10:01", text: "   "),
            .user(id: "msg-3", time: "10:02", text: "二次函数最值怎么做"),
            assistant(spans: [
                SpanData(id: "span-2", content: "先配方", sourceQuestion: "q"),
                SpanData(id: "span-3", content: "再求顶点", sourceQuestion: "q")
            ], id: "msg-4")
        ]
        let requestMessages = toArkMessages(messages)
        XCTAssertEqual(requestMessages.count, 2)
        XCTAssertEqual(requestMessages[0].role, "user")
        XCTAssertEqual(requestMessages[1].role, "assistant")
        XCTAssertTrue(requestMessages[1].text.contains("先配方"))
    }

    func testToArkMessagesPrefersMainSpanAsAssistantQuestionScopeText() {
        let messages: [ChatMessage] = [
            .user(id: "msg-1", time: "10:00", text: "题目"),
            assistant(spans: [
                SpanData(id: "span-1", content: "第一段", sourceQuestion: "题目"),
                SpanData(id: "span-2", content: "第二段", sourceQuestion: "题目")
            ], mainSpan: SpanData(id: "span-main", content: "整题统一回答", sourceQuestion: "题目"))
        ]
        let requestMessages = toArkMessages(messages)
        XCTAssertEqual(requestMessages.count, 2)
        XCTAssertEqual(requestMessages[1].text, "整题统一回答")
    }

    func testToSpanFollowupMessagesContainsContextHistoryAndFollowup() {
        let span = SpanData(id: "span-1", content: "这是段落", sourceQuestion: "完整题目")
        let conversation: [ChatMessage] = [
            .user(id: "msg-1", time: "10:00", text: "完整题目"),
            assistant(spans: [span, SpanData(id: "span-2", content: "补充说明", sourceQuestion: "完整题目")], id: "msg-2")
        ]
        let details = [
            SpanDetail(id: "detail-1", mode: "自动讲解", time: "10:00", question: "q1", answer: "a1", parentDetailId: nil, summary: nil),
            SpanDetail(id: "detail-2", mode: "自动讲解", time: "10:01", question: "q2", answer: "a2", parentDetailId: nil, summary: nil)
        ]
        let messages = toSpanFollowupMessages(span: span, followupQuestion: "新的追问", details: details, messages: conversation)
        XCTAssertTrue(messages.first!.text.contains("题目：完整题目"))
        XCTAssertTrue(messages.first!.text.contains("该题完整回答：这是段落"))
        XCTAssertTrue(messages.first!.text.contains("补充说明"))
        XCTAssertTrue(messages.first!.text.contains("这是段落"))
        XCTAssertFalse(messages.first!.text.contains("只讨论这一段"))
        XCTAssertEqual(messages.last?.text, "新的追问")
        XCTAssertTrue(messages.contains { $0.text == "q1" })
        XCTAssertTrue(messages.contains { $0.text == "a2" })
    }

    func testToSpanFollowupMessagesUsesSourceUserQuestionWhenSpanQuestionBlank() {
        let span = SpanData(id: "span-1", content: "这是段落", sourceQuestion: "   ")
        let conversation: [ChatMessage] = [
            .user(id: "msg-1", time: "10:00", text: "原题：求二次函数的最值"),
            assistant(spans: [span], id: "msg-2")
        ]
        let messages = toSpanFollowupMessages(span: span, followupQuestion: "继续追问", details: [], messages: conversation)
        XCTAssertTrue(messages.first!.text.contains("题目：原题：求二次函数的最值"))
        XCTAssertFalse(messages.first!.text.contains("原题缺失"))
    }

    func testSplitParagraphsPrefersBlankLineBlocks() {
        let content = "第一段\n\n第二段\n\n第三段"
        XCTAssertEqual(splitParagraphs(content), ["第一段", "第二段", "第三段"])
    }

    func testPrependAnkiCardPrependsAndDeduplicates() {
        let existing = [
            AnkiCard(id: "card-1", front: "Q1", back: "A1", tags: [], source: "s", createdAt: 1),
            AnkiCard(id: "card-2", front: "Q2", back: "A2", tags: [], source: "s", createdAt: 2)
        ]
        let duplicate = AnkiCard(id: "card-3", front: "Q1", back: "A1", tags: ["代数"], source: "new", createdAt: 3)
        let merged = prependAnkiCard(existing, card: duplicate)
        XCTAssertEqual(merged.first?.id, "card-3")
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.allSatisfy { $0.id != "card-1" })
    }

    func testSortAnkiCardsForReviewOrdersByMasteryThenRecency() {
        let cards = [
            AnkiCard(id: "card-1", front: "Q1", back: "A1", tags: [], source: "s", createdAt: 10, mastery: .unrated),
            AnkiCard(id: "card-2", front: "Q2", back: "A2", tags: [], source: "s", createdAt: 50, mastery: .proficient),
            AnkiCard(id: "card-3", front: "Q3", back: "A3", tags: [], source: "s", createdAt: 30, mastery: .needsWork),
            AnkiCard(id: "card-4", front: "Q4", back: "A4", tags: [], source: "s", createdAt: 40, mastery: .unrated)
        ]
        let ordered = sortAnkiCardsForReview(cards)
        XCTAssertEqual(ordered.map { $0.id }, ["card-4", "card-1", "card-3", "card-2"])
    }

    func testApplySrsReviewUpdatesReviewCountersAndNextSchedule() {
        let dayMillis: Int64 = 24 * 60 * 60 * 1000
        let base = AnkiCard(id: "card-1", front: "Q", back: "A", tags: [], source: "s", createdAt: 1)
        let reviewed = applySrsReview(base, mastery: .needsWork, reviewedAt: 2000)
        XCTAssertEqual(reviewed.mastery, .needsWork)
        XCTAssertEqual(reviewed.reviewCount, 1)
        XCTAssertEqual(reviewed.lastReviewedAt, 2000)
        XCTAssertEqual(reviewed.nextReviewAt, 2000 + dayMillis)
        let reviewedAgain = applySrsReview(reviewed, mastery: .proficient, reviewedAt: 5000)
        XCTAssertEqual(reviewedAgain.mastery, .proficient)
        XCTAssertEqual(reviewedAgain.reviewCount, 2)
        XCTAssertEqual(reviewedAgain.lastReviewedAt, 5000)
        XCTAssertEqual(reviewedAgain.nextReviewAt, 5000 + 7 * dayMillis)
    }

    func testDueReviewCardsFiltersFutureCardsAndSortsByDueTime() {
        let now: Int64 = 1_000_000
        let cards = [
            AnkiCard(id: "card-1", front: "Q1", back: "A1", tags: [], source: "s", createdAt: 10, nextReviewAt: 900_000, mastery: .familiar),
            AnkiCard(id: "card-2", front: "Q2", back: "A2", tags: [], source: "s", createdAt: 20, nextReviewAt: 800_000, mastery: .needsWork),
            AnkiCard(id: "card-3", front: "Q3", back: "A3", tags: [], source: "s", createdAt: 30, nextReviewAt: 1_200_000, mastery: .unrated)
        ]
        let due = dueReviewCards(cards, now: now)
        XCTAssertEqual(due.map { $0.id }, ["card-2", "card-1"])
        XCTAssertEqual(countDueReviewCards(cards, now: now), 2)
    }

    func testMergeGlobalAnkiCardsMergesAcrossSessionsByCardContent() {
        let now: Int64 = 10_000
        let sessionA = StoredSession(
            id: "session-a", title: "A", createdAt: 1, updatedAt: 2,
            messages: [], histories: [:], profile: ProfileState(level: "高二 · 进阶冲刺"),
            input: "", coachInput: "", activePage: .chat, quickFollowupSpanId: nil, quickFollowupDetailId: nil,
            coachMessages: [], coachDigest: nil, dailyTraining: DailyTrainingState(),
            savedQuestions: [], knowledgePoints: [:],
            ankiCards: [AnkiCard(id: "card-1", front: "同一题", back: "同一答", tags: ["函数"], source: "s", createdAt: now, nextReviewAt: now, reviewCount: 1, lastReviewedAt: now, mastery: .unrated, deckName: "函数")]
        )
        let sessionB = StoredSession(
            id: "session-b", title: "B", createdAt: 3, updatedAt: 4,
            messages: [], histories: [:], profile: ProfileState(level: "高二 · 进阶冲刺"),
            input: "", coachInput: "", activePage: .chat, quickFollowupSpanId: nil, quickFollowupDetailId: nil,
            coachMessages: [], coachDigest: nil, dailyTraining: DailyTrainingState(),
            savedQuestions: [], knowledgePoints: [:],
            ankiCards: [
                AnkiCard(id: "card-2", front: "同一题", back: "同一答", tags: ["导数"], source: "s", createdAt: now + 100, nextReviewAt: now + 100, reviewCount: 3, lastReviewedAt: now + 100, mastery: .unrated, deckName: "导数"),
                AnkiCard(id: "card-3", front: "另一题", back: "另一答", tags: [], source: "s", createdAt: now + 200)
            ]
        )
        let merged = mergeGlobalAnkiCards([sessionA, sessionB])
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains { $0.front == "同一题" && $0.reviewCount == 3 && $0.deckName == "导数" })
        XCTAssertTrue(merged.contains { $0.front == "另一题" })
    }

    func testInferKnowledgePointsFiltersOutGenericMethodText() {
        XCTAssertTrue(inferKnowledgePoints("这题的审题思路还是有点乱").isEmpty)
    }

    func testParseAiAnkiCardPayloadFiltersNonStudyTags() {
        let payload = parseAiAnkiCardPayload("""
        {"skip":false,"front":"f","back":"b","tags":["审题","函数与图像","方法总结","电场强度"],"deck":"方法总结"}
        """)
        XCTAssertEqual(payload?.tags, ["函数与图像", "电磁学"])
    }

    func testResolveDeckNameForAutoCardIgnoresGenericSuggestion() {
        let deck = resolveDeckNameForAutoCard(suggestedDeck: "方法总结", tags: [], existingCards: [])
        XCTAssertEqual(deck, DEFAULT_ANKI_DECK_NAME)
    }

    func testFilterToHighSchoolKnowledgeTagsKeepsCanonicalPointLabelsStable() {
        let tags = filterToHighSchoolKnowledgeTags(["电磁学", "导数与应用"], maxSize: 6)
        XCTAssertEqual(tags, ["电磁学", "导数与应用"])
    }

    func testSanitizeStoredSessionRemovesDirtyKnowledgeTagsAndDecks() {
        let session = StoredSession(
            id: "session-1", title: "主界面", createdAt: 1, updatedAt: 2,
            messages: [], histories: [:], profile: ProfileState(level: "高二"),
            input: "", coachInput: "", activePage: .chat, quickFollowupSpanId: nil, quickFollowupDetailId: nil,
            coachMessages: [], coachDigest: nil, dailyTraining: DailyTrainingState(),
            savedQuestions: [
                SavedQuestion(id: "saved-1", sourceMessageId: "msg-1", question: " 这题怎么做 ", answer: " 先看函数图像 ", sourceTime: "10:00", savedAt: 3, knowledgeTags: ["审题", "导数"]),
                SavedQuestion(id: "saved-2", sourceMessageId: "msg-2", question: "   ", answer: "会被清掉", sourceTime: "10:01", savedAt: 4)
            ],
            knowledgePoints: ["审题": 3, "导数": 2, "函数": 1],
            ankiCards: [AnkiCard(id: "card-1", front: "q", back: "a", tags: ["方法总结", "导数"], source: "src", createdAt: 5, deckName: "方法总结")]
        )
        let sanitized = sanitizeStoredSession(session)
        XCTAssertEqual(sanitized.savedQuestions.count, 1)
        XCTAssertEqual(sanitized.savedQuestions.first?.knowledgeTags, ["函数与图像", "导数与应用"])
        XCTAssertEqual(sanitized.knowledgePoints, ["函数与图像": 3, "导数与应用": 2])
        XCTAssertEqual(sanitized.ankiCards.first?.tags, ["函数与图像", "导数与应用"])
        XCTAssertEqual(sanitized.ankiCards.first?.deckName, "函数与图像卡组")
    }

    func testResolveDeckNameForAutoCardPrefersExistingDeckBySuggestionOrTagOverlap() {
        let existing = [
            AnkiCard(id: "card-1", front: "Q1", back: "A1", tags: ["函数", "导数"], source: "s", createdAt: 1, deckName: "函数"),
            AnkiCard(id: "card-2", front: "Q2", back: "A2", tags: ["电磁", "电流"], source: "s", createdAt: 2, deckName: "电学")
        ]
        let bySuggestion = resolveDeckNameForAutoCard(suggestedDeck: "函数", tags: ["代数"], existingCards: existing)
        let byOverlap = resolveDeckNameForAutoCard(suggestedDeck: nil, tags: ["电流", "欧姆定律"], existingCards: existing)
        XCTAssertEqual(bySuggestion, "函数")
        XCTAssertEqual(byOverlap, "电学")
    }

    func testResolveDeckNameForAutoCardCreatesDeckWhenNoExistingMatch() {
        let existing = [AnkiCard(id: "card-1", front: "Q1", back: "A1", tags: ["函数"], source: "s", createdAt: 1, deckName: "函数")]
        let newDeck = resolveDeckNameForAutoCard(suggestedDeck: nil, tags: ["化学平衡"], existingCards: existing)
        XCTAssertTrue(newDeck.hasSuffix("卡组"))
        XCTAssertTrue(newDeck.contains("化学"))
    }

    func testBuildAnkiDeckSummariesGroupsAndSortsByCardCount() {
        let cards = [
            AnkiCard(id: "card-1", front: "Q1", back: "A1", tags: [], source: "s", createdAt: 1, deckName: "函数"),
            AnkiCard(id: "card-2", front: "Q2", back: "A2", tags: [], source: "s", createdAt: 2, deckName: "函数"),
            AnkiCard(id: "card-3", front: "Q3", back: "A3", tags: [], source: "s", createdAt: 3, deckName: "电学")
        ]
        let summaries = buildAnkiDeckSummaries(cards)
        XCTAssertEqual(summaries.map { $0.name }, ["函数", "电学"])
        XCTAssertEqual(summaries.map { $0.cardCount }, [2, 1])
    }

    func testBuildSessionTitleUsesUserMessageOrFallbackTime() {
        let withUser: [ChatMessage] = [.user(id: "msg-1", time: "10:00", text: "  这是一个很长很长的问题标题会被截断  ")]
        let withoutUser: [ChatMessage] = [assistant(spans: [SpanData(id: "span-1", content: "内容", sourceQuestion: "q")])]
        XCTAssertEqual(buildSessionTitle(withUser, fallbackTime: "11:22"), "这是一个很长很长的问题标题会被截断")
        XCTAssertEqual(buildSessionTitle(withoutUser, fallbackTime: "11:22"), "新会话 11:22")
    }

    func testBuildSyncedSessionSnapshotReusesCreatedAtAndUpdatesTitle() {
        var s = RuntimeSettings.defaults()
        let state = ChatUiState(messages: [.user(id: "msg-1", time: "10:00", text: "极限题怎么做")], activeSessionId: "session-1", settings: s, settingsDraft: s)
        _ = s
        let synced = buildSyncedSessionSnapshot(state: state, fallbackTime: "11:22", now: 200, existingCreatedAt: 100)
        XCTAssertEqual(synced.id, "session-1")
        XCTAssertEqual(synced.title, "极限题怎么做")
        XCTAssertEqual(synced.createdAt, 100)
        XCTAssertEqual(synced.updatedAt, 200)
    }

    func testBuildPersistedSessionsPayloadHandlesBlankAndActiveSessionId() {
        var s = RuntimeSettings.defaults()
        s.arkApiKey = "test-key"
        let blankState = ChatUiState(activeSessionId: "  ", settings: s, settingsDraft: s)
        XCTAssertNil(buildPersistedSessionsPayload(state: blankState, sessions: []))
        let activeState = ChatUiState(activeSessionId: "session-2", settings: s, settingsDraft: s)
        let stored = toStoredSessionSnapshot(state: activeState, title: "会话", createdAt: 1, updatedAt: 2)
        let payload = buildPersistedSessionsPayload(state: activeState, sessions: [stored])
        XCTAssertEqual(payload?.activeSessionId, "session-2")
        XCTAssertEqual(payload?.settings.arkApiKey, "test-key")
        XCTAssertEqual(payload?.sessions.count, 1)
    }

    func testStoredSessionSnapshotAndBuildUiStateKeepQuickFollowupSpanId() {
        var s = RuntimeSettings.defaults()
        // ChatUiState 成员式初始化需按属性声明顺序传参：quickFollowupSpanId/DetailId → activePage → activeSessionId
        let state = ChatUiState(quickFollowupSpanId: "span-9", quickFollowupDetailId: "detail-4", activePage: .quickFollowup, activeSessionId: "session-quick", settings: s, settingsDraft: s)
        _ = s
        let snapshot = toStoredSessionSnapshot(state: state, title: "精细追问", createdAt: 11, updatedAt: 12)
        let rebuilt = buildUiStateFromSession(session: snapshot, ankiCards: [], settings: RuntimeSettings.defaults(), toastMessage: nil)
        XCTAssertEqual(snapshot.quickFollowupSpanId, "span-9")
        XCTAssertEqual(snapshot.quickFollowupDetailId, "detail-4")
        XCTAssertEqual(rebuilt.activePage, .quickFollowup)
        XCTAssertEqual(rebuilt.quickFollowupSpanId, "span-9")
        XCTAssertEqual(rebuilt.quickFollowupDetailId, "detail-4")
    }

    func testDeriveSessionSeedsReturnsMaxNumericSuffixes() {
        var s = RuntimeSettings.defaults()
        let state = ChatUiState(
            messages: [
                .user(id: "msg-3", time: "10:00", text: "q"),
                .assistant(id: "msg-7", time: "10:01", spans: [SpanData(id: "span-2", content: "a", sourceQuestion: "q"), SpanData(id: "span-9", content: "b", sourceQuestion: "q")])
            ],
            histories: ["span-9": [SpanDetail(id: "detail-4", mode: "自动讲解", time: "10:02", question: nil, answer: "a", parentDetailId: nil, summary: nil)]],
            ankiCards: [AnkiCard(id: "card-6", front: "q", back: "a", tags: [], source: "src", createdAt: 1)],
            activeSessionId: "session-1", settings: s, settingsDraft: s
        )
        _ = s
        let session = toStoredSessionSnapshot(state: state, title: "会话", createdAt: 1, updatedAt: 2)
        let seeds = deriveSessionSeeds(session)
        XCTAssertEqual(seeds.messageSeed, 7)
        XCTAssertEqual(seeds.spanSeed, 9)
        XCTAssertEqual(seeds.detailSeed, 4)
        XCTAssertEqual(seeds.cardSeed, 6)
    }

    func testSpanProcessingHelpersUpdateProcessingAndHistory() {
        var s = RuntimeSettings.defaults()
        let base = ChatUiState(histories: ["span-1": [SpanDetail(id: "detail-1", mode: "自动讲解", time: "10:00", question: nil, answer: "old", parentDetailId: nil, summary: nil)]], settings: s, settingsDraft: s)
        _ = s
        let marked = markSpanProcessing(base, spanId: "span-1")
        let appended = appendSpanDetailHistory(current: marked, spanId: "span-1", detail: SpanDetail(id: "detail-2", mode: "追问", time: "10:01", question: "q", answer: "new", parentDetailId: nil, summary: nil), toastMessage: "done")
        let cleared = clearSpanProcessing(appended, spanId: "span-1", toastMessage: "cleared")
        XCTAssertTrue(marked.processingSpanIds.contains("span-1"))
        XCTAssertEqual(appended.histories["span-1"]?.first?.id, "detail-2")
        XCTAssertEqual(appended.toastMessage, "done")
        XCTAssertTrue(cleared.processingSpanIds.isEmpty)
        XCTAssertEqual(cleared.toastMessage, "cleared")
    }

    func testUpsertAndRemoveSpanDetailHistoryReplaceAndDeleteById() {
        var s = RuntimeSettings.defaults()
        let base = ChatUiState(histories: ["span-1": [SpanDetail(id: "detail-1", mode: "自动讲解", time: "10:00", question: nil, answer: "old", parentDetailId: nil, summary: nil)]], settings: s, settingsDraft: s)
        _ = s
        let replaced = upsertSpanDetailHistory(current: base, spanId: "span-1", detail: SpanDetail(id: "detail-1", mode: "自动讲解", time: "10:01", question: nil, answer: "new", parentDetailId: nil, summary: nil))
        let removed = removeSpanDetailHistory(current: replaced, spanId: "span-1", detailId: "detail-1")
        XCTAssertEqual(replaced.histories["span-1"]?.first?.answer, "new")
        XCTAssertTrue((removed.histories["span-1"] ?? []).isEmpty)
    }

    func testIsTokenStaleDetectsTokenMismatch() {
        XCTAssertTrue(isTokenStale(requestToken: 2, activeToken: 3))
        XCTAssertFalse(isTokenStale(requestToken: 5, activeToken: 5))
    }

    func testDeliverTokenAwareResultStaleTokenOnlyTriggersStaleCallback() {
        var staleCalled = false
        var successCalled = false
        var failureCalled = false
        deliverTokenAwareResult(Result<String, Error>.success("ok"), requestToken: 10, activeToken: 11,
            onStale: { staleCalled = true },
            onSuccess: { _ in successCalled = true },
            onFailure: { _ in failureCalled = true })
        XCTAssertTrue(staleCalled)
        XCTAssertFalse(successCalled)
        XCTAssertFalse(failureCalled)
    }

    func testDeliverTokenAwareResultMatchingTokenRoutesResultCallbacks() {
        var successValue: String? = nil
        var failureValue: Error? = nil
        deliverTokenAwareResult(.success("done"), requestToken: 12, activeToken: 12,
            onStale: { XCTFail("stale") },
            onSuccess: { value in successValue = value },
            onFailure: { error in failureValue = error })
        XCTAssertEqual(successValue, "done")
        XCTAssertNil(failureValue)
    }

    func testExtractFencedJsonCandidateParsesMarkdownFencedJson() {
        let raw = """
        ```json
        {
          "skip": false,
          "front": "牛顿第二定律",
          "back": "F=ma",
          "tags": ["物理", "力学"]
        }
        ```
        """
        let json = extractFencedJsonCandidate(raw)
        let expected = """
        {
          "skip": false,
          "front": "牛顿第二定律",
          "back": "F=ma",
          "tags": ["物理", "力学"]
        }
        """
        XCTAssertEqual(json, expected)
    }

    func testParseImageQuestionArchivePayloadParsesQuestionTypeAndTags() {
        let payload = parseImageQuestionArchivePayload("""
        {
          "question": "已知二次函数 y=ax^2+bx+c，求最值并判断单调区间。",
          "subject": "数学",
          "question_type": "解答题",
          "knowledge_tags": ["二次函数", "函数与图像", "套路"],
          "analysis_summary": "重点考查二次函数图像与最值判断，容易漏掉对称轴。"
        }
        """)
        XCTAssertEqual(payload?.subject, "数学")
        XCTAssertEqual(payload?.questionType, "解答题")
        XCTAssertEqual(payload?.knowledgeTags, ["二次函数", "函数与图像"])
    }

    func testBuildFallbackImageArchivePayloadPrefersNonGenericQuestionTitle() {
        let payload = buildFallbackImageArchivePayload(
            sourceQuestion: "拍照搜题：请识别并讲解这道题",
            answer: "题目：已知二次函数 y=ax^2+bx+c，求最值并判断单调区间。先找对称轴。"
        )
        XCTAssertTrue(payload.question.contains("二次函数") || payload.question.contains("最值"))
        XCTAssertFalse(payload.analysisSummary.isEmpty)
    }

    func testResolveErrorHintUsesFallbackAndTruncatesMessage() {
        let fallback = resolveErrorHint(nil, fallback: "网络不可用")
        let longMessage = String(repeating: "x", count: 120)
        let resolved = resolveErrorHint(RuntimeError(longMessage), fallback: "unused")
        XCTAssertEqual(fallback, "网络不可用")
        XCTAssertEqual(resolved.count, 80)
    }

    func testResolveErrorHintMapsSoftwareAbortToFriendlyText() {
        let resolved = resolveErrorHint(RuntimeError("Software caused connection abort"), fallback: "网络不可用")
        XCTAssertEqual(resolved, "网络连接中断，请重试")
    }
}
