import SwiftUI
import Combine
import PhotosUI

/// 错误条的可操作类型
enum ErrorBannerAction {
    case openSettings
    case none
}

/// 中央 view model，驱动 iOS 移植版。持有活跃的 ChatUiState、通过 SessionStore
/// 持久化会话，并编排 ARK 请求与段落追问。
@MainActor
final class AppState: ObservableObject {
    @Published var state: ChatUiState
    @Published var toast: String? = nil
    // 持久错误条：发问失败时显示在底部，带可操作按钮，避免用户“发了没反应”
    @Published var errorBanner: String? = nil
    @Published var errorAction: ErrorBannerAction? = nil
    @Published var photoPickerItems: [PhotosPickerItem] = []
    @Published var pendingImages: [Data] = []

    let store = SessionStore()
    let arkClient = ArkApiClient()

    private var registry = SessionRegistry()
    private var seeds = SessionSeeds(messageSeed: 0, spanSeed: 0, detailSeed: 0, cardSeed: 0)
    private var requestToken: Int64 = 0
    private var savedQuestionRegistry: [String: SavedQuestion] = [:]
    private var globalAnkiCards: [AnkiCard] = []

    init() {
        var loadedSettings = RuntimeSettings.defaults()
        var loadedSessions: [StoredSession] = []
        var activeId = ""
        if let payload = store.load() {
            loadedSettings = payload.settings
            loadedSessions = payload.sessions
            activeId = payload.activeSessionId
        }
        registry.replaceAll(loadedSessions)
        globalAnkiCards = mergeGlobalAnkiCards(loadedSessions)

        if let activeId = loadedSessions.first(where: { $0.id == activeId })?.id,
           let session = registry.get(activeId) {
            state = buildUiStateFromSession(session: session, ankiCards: globalAnkiCards, settings: loadedSettings, toastMessage: nil)
            seeds = deriveSessionSeeds(session)
        } else if let firstId = registry.firstIdOrNull(), let session = registry.get(firstId) {
            state = buildUiStateFromSession(session: session, ankiCards: globalAnkiCards, settings: loadedSettings, toastMessage: nil)
            seeds = deriveSessionSeeds(session)
        } else {
            let settings = loadedSettings
            let sessionId = "session-\(currentTimeMillis())"
            let intro = ChatMessage.assistant(
                id: "msg-1",
                time: nowTimeString(),
                spans: [SpanData(id: "span-1", content: buildIntroGuideContent(), sourceQuestion: "初始化引导")],
                mainSpan: SpanData(id: "span-1", content: buildIntroGuideContent(), sourceQuestion: "初始化引导")
            )
            seeds = SessionSeeds(messageSeed: 1, spanSeed: 1, detailSeed: 0, cardSeed: 0)
            state = createInitialSessionState(sessionId: sessionId, introMessage: intro, ankiCards: globalAnkiCards, settings: settings, settingsDraft: settings, showIntroToast: true)
            registry.put(toStoredSessionSnapshot(state: state, title: buildSessionTitle(state.messages, fallbackTime: nowTimeString()), createdAt: currentTimeMillis(), updatedAt: currentTimeMillis()), moveToFront: true)
        }
        rebuildSavedQuestionRegistry()
    }

    // MARK: - Sessions

    func startNewSession() {
        let sessionId = "session-\(currentTimeMillis())"
        let msgId = nextMessageId()
        let spanId = nextSpanId()
        let intro = ChatMessage.assistant(
            id: msgId,
            time: nowTimeString(),
            spans: [SpanData(id: spanId, content: buildIntroGuideContent(), sourceQuestion: "初始化引导")],
            mainSpan: SpanData(id: spanId, content: buildIntroGuideContent(), sourceQuestion: "初始化引导")
        )
        let settings = state.settings
        state = createInitialSessionState(sessionId: sessionId, introMessage: intro, ankiCards: globalAnkiCards, settings: settings, settingsDraft: settings, showIntroToast: true)
        registry.put(toStoredSessionSnapshot(state: state, title: buildSessionTitle(state.messages, fallbackTime: nowTimeString()), createdAt: currentTimeMillis(), updatedAt: currentTimeMillis()), moveToFront: true)
        persist()
    }

    func switchToSession(id: String) {
        guard let session = registry.get(id) else { return }
        state = buildUiStateFromSession(session: session, ankiCards: globalAnkiCards, settings: state.settings, toastMessage: nil)
        seeds = deriveSessionSeeds(session)
        registry.touch(id)
        persist()
    }

    func deleteSession(id: String) {
        registry.remove(id)
        globalAnkiCards = mergeGlobalAnkiCards(registry.orderedSessions())
        if state.activeSessionId == id {
            if let firstId = registry.firstIdOrNull(), let session = registry.get(firstId) {
                state = buildUiStateFromSession(session: session, ankiCards: globalAnkiCards, settings: state.settings, toastMessage: nil)
                seeds = deriveSessionSeeds(session)
            } else {
                startNewSession()
            }
        }
        persist()
    }

    var orderedSessions: [StoredSession] { return registry.orderedSessions() }

    // MARK: - Sending questions

    func sendTextQuestion() async {
        let question = state.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let userMessage = ChatMessage.user(id: nextMessageId(), time: nowTimeString(), text: question)
        state = queueQuestionState(current: state, userMessage: userMessage, question: question, isFollowup: false, isVoice: false, clearInput: true)
        await runArkRequest(messages: toArkMessages(state.messages))
    }

    func sendImageQuestion(prompt: String) async {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { "拍照搜题：请识别并讲解这道题" }
        guard !pendingImages.isEmpty else { return }
        let images = toImagePayloads(pendingImages)
        let userMessage = ChatMessage.user(id: nextMessageId(), time: nowTimeString(), text: normalized, imagePreviewList: pendingImages)
        state = queueImageQuestionState(current: state, userMessage: userMessage, question: normalized, source: normalized)
        persist()
        requestToken += 1
        let token = requestToken
        state.isLoading = true
        let config = state.settings.toArkRuntimeConfig()
        let imagePrompt = normalizeImagePrompt(state.settings.imagePrompt)
        let result = await arkClient.generateReplyWithImages(prompt: imagePrompt, images: images, config: config, stream: true, onDelta: { [weak self] delta in
            Task { @MainActor in self?.appendStreamDelta(delta) }
        })
        state.isLoading = false
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] _ in Task { @MainActor in self?.finalizeAssistant() } },
            onFailure: { [weak self] error in Task { @MainActor in self?.handleFailure(error) } }
        )
    }

    private func runArkRequest(messages: [ArkRequestMessage]) async {
        requestToken += 1
        let token = requestToken
        state.isLoading = true
        streamAssistantId = nextMessageId()
        streamSpanId = nextSpanId()
        streamText = ""
        let config = state.settings.toArkRuntimeConfig()
        let result = await arkClient.generateReplyStream(messages: messages, config: config, onDelta: { [weak self] delta in
            Task { @MainActor in self?.appendStreamDelta(delta) }
        })
        state.isLoading = false
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] _ in Task { @MainActor in self?.finalizeAssistant() } },
            onFailure: { [weak self] error in Task { @MainActor in self?.handleFailure(error) } }
        )
    }

    // MARK: - Swipe-driven span actions

    func autoExplain(spanId: String) async {
        guard let span = findSpanById(state.messages, spanId: spanId) else { return }
        let prompt = buildAutoExplainPrompt(span.content)
        let messages = toSpanFollowupMessages(span: span, followupQuestion: prompt, details: state.histories[spanId] ?? [], messages: state.messages)
        state = markSpanProcessing(state, spanId: spanId)
        persist()
        requestToken += 1
        let token = requestToken
        let config = state.settings.toArkRuntimeConfig()
        let detailId = nextDetailId()
        let result = await arkClient.generateReplyStream(messages: messages, config: config, onDelta: { [weak self] delta in
            Task { @MainActor in self?.appendDetailDelta(spanId: spanId, detailId: detailId, delta: delta) }
        })
        let detail = SpanDetail(id: detailId, mode: "自动讲解", time: nowTimeString(), question: prompt, answer: streamBuffer[detailId] ?? "", parentDetailId: nil, summary: nil)
        streamBuffer.removeValue(forKey: detailId)
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] _ in Task { @MainActor in self?.finishSpanDetail(spanId: spanId, detail: detail) } },
            onFailure: { [weak self] error in Task { @MainActor in self?.failSpanDetail(spanId: spanId, error: error) } }
        )
    }

    func quickFollowup(spanId: String, question: String, isVoice: Bool) async {
        guard let span = findSpanById(state.messages, spanId: spanId) else { return }
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        state = queueSpanFollowupState(current: state, spanId: spanId, question: normalized, isVoice: isVoice)
        persist()
        requestToken += 1
        let token = requestToken
        let messages = toSpanFollowupMessages(span: span, followupQuestion: normalized, details: state.histories[spanId] ?? [], messages: state.messages)
        let config = state.settings.toArkRuntimeConfig()
        let detailId = nextDetailId()
        let result = await arkClient.generateReplyStream(messages: messages, config: config, onDelta: { [weak self] delta in
            Task { @MainActor in self?.appendDetailDelta(spanId: spanId, detailId: detailId, delta: delta) }
        })
        let detail = SpanDetail(id: detailId, mode: isVoice ? "语音追问" : "精细追问", time: nowTimeString(), question: normalized, answer: streamBuffer[detailId] ?? "", parentDetailId: nil, summary: nil)
        streamBuffer.removeValue(forKey: detailId)
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] _ in Task { @MainActor in self?.finishSpanDetail(spanId: spanId, detail: detail) } },
            onFailure: { [weak self] error in Task { @MainActor in self?.failSpanDetail(spanId: spanId, error: error) } }
        )
    }

    // MARK: - Streaming accumulation

    private var streamAssistantId: String? = nil
    private var streamSpanId: String? = nil
    private var streamText = ""
    private var streamBuffer: [String: String] = [:]

    private func appendStreamDelta(_ delta: String) {
        streamText += delta
        guard let assistantId = streamAssistantId, let spanId = streamSpanId else { return }
        let span = SpanData(id: spanId, content: streamText, sourceQuestion: latestUserQuestion())
        let assistant = ChatMessage.assistant(id: assistantId, time: nowTimeString(), spans: [span], mainSpan: span)
        state = upsertAssistantMessageState(current: state, assistantMessage: assistant)
    }

    private func appendDetailDelta(spanId: String, detailId: String, delta: String) {
        streamBuffer[detailId, default: ""] += delta
        let detail = SpanDetail(id: detailId, mode: "生成中", time: nowTimeString(), question: nil, answer: streamBuffer[detailId] ?? "", parentDetailId: nil, summary: nil)
        state = upsertSpanDetailHistory(current: state, spanId: spanId, detail: detail)
    }

    private func finalizeAssistant() {
        let text = streamText
        let assistantId = streamAssistantId ?? nextMessageId()
        let spanId = streamSpanId ?? nextSpanId()
        let span = SpanData(id: spanId, content: text, sourceQuestion: latestUserQuestion())
        let assistant = ChatMessage.assistant(id: assistantId, time: nowTimeString(), spans: [span], mainSpan: span)
        state = appendAssistantMessageState(current: state, assistantMessage: assistant, toastMessage: "已生成回答")
        errorBanner = nil
        errorAction = nil
        streamText = ""
        streamAssistantId = nil
        streamSpanId = nil
        persist()
    }

    private func finishSpanDetail(spanId: String, detail: SpanDetail) {
        state = upsertSpanDetailHistory(current: state, spanId: spanId, detail: detail, clearProcessing: true, toastMessage: "已完成")
        errorBanner = nil
        errorAction = nil
        persist()
    }

    private func failSpanDetail(spanId: String, error: Error) {
        state = clearSpanProcessing(state, spanId: spanId, toastMessage: "失败：\(resolveErrorHint(error, fallback: "网络不可用"))")
        streamBuffer.removeAll()
        persist()
    }

    private func handleFailure(_ error: Error) {
        let hint = resolveErrorHint(error, fallback: "网络不可用")
        state.toastMessage = "回答失败：\(hint)"
        toast = state.toastMessage
        // 不再回滚用户消息：保留在列表里，让用户看到自己问了什么；改用持久错误条提示
        errorAction = hint.contains("设置") ? .openSettings : .none
        errorBanner = "回答失败：\(hint)"
        streamText = ""
        streamAssistantId = nil
        persist()
    }

    func dismissErrorBanner() {
        errorBanner = nil
        errorAction = nil
    }

    private func latestUserQuestion() -> String {
        for message in state.messages.reversed() {
            if case .user(_, _, let text, _, _) = message {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    private func lastUserIdQuestion() -> String {
        return latestUserQuestion()
    }

    // MARK: - Archive / Anki / Coach

    func saveCurrentQuestion() {
        guard let assistant = state.messages.last(where: { if case .assistant = $0 { return true }; return false }) else { return }
        let saved = SavedQuestion(
            id: "saved-\(currentTimeMillis())",
            sourceMessageId: assistant.id,
            question: latestUserQuestion(),
            answer: assistant.fullAnswerText(),
            sourceTime: nowTimeString(),
            savedAt: currentTimeMillis(),
            followupCount: 0,
            knowledgeTags: filterToHighSchoolKnowledgeTags(inferKnowledgePoints(assistant.fullAnswerText()), maxSize: 6)
        )
        guard let sanitized = sanitizeSavedQuestion(saved) else { return }
        state.savedQuestions = [sanitized] + state.savedQuestions.filter { $0.id != sanitized.id }
        rebuildSavedQuestionRegistry()
        state.toastMessage = "已收藏本题"
        toast = state.toastMessage
        persist()
    }

    func generateCoachDigest() {
        let digest = buildCoachDailyDigest(
            messages: state.messages,
            histories: state.histories,
            savedQuestions: state.savedQuestions,
            knowledgePoints: state.knowledgePoints
        )
        state.coachDigest = digest
        persist()
    }

    func sendCoachMessage(_ text: String) async {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let userMessage = CoachChatMessage(id: nextMessageId(), role: .user, time: nowTimeString(), text: normalized)
        state.coachMessages = upsertCoachMessage(state.coachMessages, target: userMessage)
        state.coachInput = ""
        let insights = buildKnowledgeGapInsights(messages: state.messages, histories: state.histories, knowledgePoints: state.knowledgePoints)
        let messages = buildCoachConversationMessages(
            digest: state.coachDigest,
            coachMessages: state.coachMessages,
            profile: state.profile,
            knowledgePoints: state.knowledgePoints,
            knowledgeGapInsights: insights,
            savedQuestions: state.savedQuestions
        )
        requestToken += 1
        let token = requestToken
        let config = state.settings.toArkRuntimeConfig()
        let assistantId = nextMessageId()
        let result = await arkClient.generateReplyStream(messages: messages, config: config, onDelta: { [weak self] delta in
            Task { @MainActor in
                guard let self = self else { return }
                self.coachBuffer += delta
                let assistant = CoachChatMessage(id: assistantId, role: .assistant, time: nowTimeString(), text: self.coachBuffer)
                self.state.coachMessages = upsertCoachMessage(self.state.coachMessages, target: assistant)
            }
        })
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] _ in Task { @MainActor in self?.finalizeCoachMessage(id: assistantId) } },
            onFailure: { [weak self] error in Task { @MainActor in self?.handleFailure(error) } }
        )
    }

    private var coachBuffer = ""

    private func finalizeCoachMessage(id: String) {
        let assistant = CoachChatMessage(id: id, role: .assistant, time: nowTimeString(), text: coachBuffer)
        state.coachMessages = upsertCoachMessage(state.coachMessages, target: assistant)
        coachBuffer = ""
        errorBanner = nil
        errorAction = nil
        persist()
    }

    func reviewAnkiCard(_ card: AnkiCard, mastery: CardMasteryLevel) {
        guard let index = state.ankiCards.firstIndex(where: { $0.id == card.id }) else { return }
        let reviewed = applySrsReview(card, mastery: mastery)
        state.ankiCards[index] = reviewed
        globalAnkiCards = mergeGlobalAnkiCards(registry.orderedSessions() + [toStoredSessionSnapshot(state: state, title: buildSessionTitle(state.messages, fallbackTime: nowTimeString()), createdAt: currentTimeMillis(), updatedAt: currentTimeMillis())])
        persist()
    }

    // MARK: - Settings

    func openSettings() { state.isSettingsOpen = true }
    func cancelSettings() { state.settingsDraft = state.settings; state.isSettingsOpen = false }
    func saveSettings() { state.settings = state.settingsDraft; state.isSettingsOpen = false; persist() }

    /// 用当前草稿配置发起一次轻量连通性测试（非流式，发一个 ping）
    @Published var connectionTestResult: String? = nil
    @Published var isTestingConnection = false

    func testConnection() async {
        let config = state.settingsDraft.toArkRuntimeConfig()
        isTestingConnection = true
        connectionTestResult = nil
        defer { isTestingConnection = false }
        let result = await arkClient.generateReply(messages: [ArkRequestMessage(role: "user", text: "ping")], config: config)
        switch result {
        case .success:
            connectionTestResult = "✅ 连接成功"
        case .failure(let error):
            connectionTestResult = "❌ " + resolveErrorHint(error, fallback: "连接失败")
        }
    }

    // MARK: - Persistence

    func persist() {
        let snapshot = buildSyncedSessionSnapshot(state: state, fallbackTime: nowTimeString(), now: currentTimeMillis(), existingCreatedAt: registry.createdAtOf(state.activeSessionId))
        registry.put(snapshot, moveToFront: true)
        globalAnkiCards = mergeGlobalAnkiCards(registry.orderedSessions())
        if let payload = buildPersistedSessionsPayload(state: state, sessions: registry.orderedSessions()) {
            _ = store.save(payload)
        }
    }

    private func rebuildSavedQuestionRegistry() {
        savedQuestionRegistry = Dictionary(uniqueKeysWithValues: state.savedQuestions.map { ($0.id, $0) })
    }

    // MARK: - Ids

    private func nextMessageId() -> String { seeds.messageSeed += 1; return "msg-\(seeds.messageSeed)" }
    private func nextSpanId() -> String { seeds.spanSeed += 1; return "span-\(seeds.spanSeed)" }
    private func nextDetailId() -> String { seeds.detailSeed += 1; return "detail-\(seeds.detailSeed)" }

    // MARK: - Photo handling

    func loadPickedImages() async {
        var images: [Data] = []
        for item in photoPickerItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                images.append(data)
            }
        }
        pendingImages = images
    }
}

private extension String {
    func ifBlank(_ fallback: () -> String) -> String {
        return isEmpty ? fallback() : self
    }
}
