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
    let flowStudyClient = FlowStudySyncClient()

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

    /// 精细追问：parentDetailId 为空时挂在段落根下，否则挂在某条追问之下形成分层
    func quickFollowup(spanId: String, question: String, isVoice: Bool, parentDetailId: String? = nil) async {
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
        let detail = SpanDetail(id: detailId, mode: isVoice ? "语音追问" : "精细追问", time: nowTimeString(), question: normalized, answer: streamBuffer[detailId] ?? "", parentDetailId: parentDetailId, summary: nil)
        streamBuffer.removeValue(forKey: detailId)
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] _ in Task { @MainActor in self?.finishSpanDetail(spanId: spanId, detail: detail) } },
            onFailure: { [weak self] error in Task { @MainActor in self?.failSpanDetail(spanId: spanId, error: error) } }
        )
    }

    // MARK: - 精细追问分层导航（对齐 Android openDetails / closeDetails / stepBackQuickFollowupLayer）

    /// 在精细追问面板里聚焦到某条追问（用于钻取下一层）
    func openDetails(spanId: String, detailId: String) {
        state.selectedSpanId = spanId
        state.selectedDetailId = detailId
        state.quickFollowupSpanId = spanId
        state.quickFollowupDetailId = detailId
        persist()
    }

    /// 关闭当前钻取，回到段落根下的追问列表
    func closeDetails() {
        state.selectedDetailId = nil
        state.quickFollowupDetailId = nil
        persist()
    }

    /// 返回上一层：若有父追问则聚焦父追问，否则回到段落根
    @discardableResult
    func stepBackQuickFollowupLayer() -> Bool {
        guard let spanId = state.quickFollowupSpanId, let detailId = state.quickFollowupDetailId else {
            closeDetails(); return false
        }
        let details = state.histories[spanId] ?? []
        if let current = details.first(where: { $0.id == detailId }), let parent = current.parentDetailId, !parent.isEmpty {
            state.quickFollowupDetailId = parent
            state.selectedDetailId = parent
        } else {
            closeDetails()
        }
        persist()
        return true
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

    // MARK: - 已收藏题目（归档）操作

    /// 切换某条助手回答的收藏状态（已收藏则取消，未收藏则新建快照）
    func toggleSavedQuestion(messageId: String) {
        if let existing = state.savedQuestions.first(where: { $0.sourceMessageId == messageId }) {
            removeSavedQuestion(savedQuestionId: existing.id)
            return
        }
        guard let saved = buildSavedQuestionSnapshot(state: state, messageId: messageId) else {
            toast = "当前题目暂时无法收藏"; state.toastMessage = toast
            return
        }
        state.savedQuestions = [saved] + state.savedQuestions.filter { $0.sourceMessageId != messageId }
        state.archiveFocusSavedQuestionId = saved.id
        rebuildSavedQuestionRegistry()
        state.toastMessage = "已收藏到题目归档"
        toast = state.toastMessage
        persist()
    }

    func removeSavedQuestion(savedQuestionId: String) {
        guard state.savedQuestions.contains(where: { $0.id == savedQuestionId }) else { return }
        state.savedQuestions = state.savedQuestions.filter { $0.id != savedQuestionId }
        if state.archiveFocusSavedQuestionId == savedQuestionId { state.archiveFocusSavedQuestionId = nil }
        state.toastMessage = "已移出题目归档"
        toast = state.toastMessage
        persist()
    }

    /// 把已收藏题目回填到提问框并切到聊天页
    func restoreSavedQuestionToComposer(savedQuestionId: String) {
        guard let saved = state.savedQuestions.first(where: { $0.id == savedQuestionId }) else {
            toast = "未找到已收藏题目"; state.toastMessage = toast; return
        }
        state.activePage = .chat
        state.input = saved.question
        state.archiveFocusSavedQuestionId = nil
        state.toastMessage = "已回填到提问框"
        toast = state.toastMessage
        persist()
    }

    /// 重新生成某条助手回答（用其上方最近的用户消息作为来源）
    func refreshAssistantReply(messageId: String) async {
        guard let assistantIndex = state.messages.firstIndex(where: {
            if case .assistant(let id, _, _, _, _) = $0 { return id == messageId }; return false
        }) else {
            toast = "未找到要刷新的回复"; state.toastMessage = toast; return
        }
        guard case .assistant(let aid, _, let spans, let mainSpan, _) = state.messages[assistantIndex] else { return }
        let rawSource = mainSpan?.sourceQuestion ?? spans.first?.sourceQuestion ?? ""
        let sourceQuestion = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        // 找到该回答上方最近一条用户消息
        let sourceUser = state.messages.prefix(assistantIndex).reversed().first(where: {
            if case .user = $0 { return true }; return false
        })
        let imageBytesList: [Data] = {
            guard let user = sourceUser, case .user(_, _, _, let bytes, let list) = user else { return [] }
            return list.isEmpty ? (bytes.map { [$0] } ?? []) : list
        }()
        // 先移除旧助手回答
        state.messages.remove(at: assistantIndex)
        if !imageBytesList.isEmpty {
            let images = toImagePayloads(imageBytesList)
            let userMessage = ChatMessage.user(id: nextMessageId(), time: nowTimeString(), text: sourceQuestion.isEmpty ? "重新识别这道题" : sourceQuestion, imagePreviewList: imageBytesList)
            state = queueImageQuestionState(current: state, userMessage: userMessage, question: sourceQuestion, source: sourceQuestion)
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
        } else {
            let question = sourceQuestion.isEmpty ? (latestUserQuestion()) : sourceQuestion
            let userMessage = ChatMessage.user(id: nextMessageId(), time: nowTimeString(), text: question)
            state = queueQuestionState(current: state, userMessage: userMessage, question: question, isFollowup: false, isVoice: false, clearInput: false)
            persist()
            await runArkRequest(messages: toArkMessages(state.messages))
        }
        // 抑制 aid 未使用警告
        _ = aid
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

    // MARK: - 教练每日训练（对齐 Android StudyCoach training flow）
    private var trainingBuffer = ""

    private func ensureCoachDigestCurrent() -> CoachDailyDigest {
        let todayKey = currentCoachDateKey()
        if let d = state.coachDigest, d.dateKey == todayKey { return d }
        let digest = buildCoachDailyDigest(
            messages: state.messages, histories: state.histories,
            savedQuestions: state.savedQuestions, knowledgePoints: state.knowledgePoints
        )
        state.coachDigest = digest
        persist()
        return digest
    }

    private func isDailyTrainingStale(_ training: DailyTrainingState) -> Bool {
        return !training.dateKey.isEmpty && training.dateKey != currentCoachDateKey()
    }

    func onCoachPageViewed() {
        if isDailyTrainingStale(state.dailyTraining) { state.dailyTraining = DailyTrainingState() }
        _ = ensureCoachDigestCurrent()
    }

    func sendCoachQuickAction(_ prompt: String) { Task { await sendCoachMessage(prompt) } }

    func askCoachAboutRecommendation(_ question: CoachRecommendedQuestion) {
        Task { await sendCoachMessage(buildCoachRecommendationFollowupPrompt(question)) }
    }

    func jumpToCoachRecommendationBasis(_ question: CoachRecommendedQuestion) {
        guard let target = question.anchorSavedQuestionId, !target.isEmpty else {
            toast = "这道题暂时还没有可跳转的依据题"; state.toastMessage = toast; return
        }
        guard state.savedQuestions.contains(where: { $0.id == target }) else {
            toast = "依据题暂未归档完成"; state.toastMessage = toast; return
        }
        state.activePage = .archive
        state.archiveFocusSavedQuestionId = target
        state.toastMessage = "已跳到教练出题依据题"
        toast = state.toastMessage
        persist()
    }

    func startCoachTraining() async {
        if state.isLoading { toast = "当前还有内容在生成，请稍等"; state.toastMessage = toast; return }
        if !isDailyTrainingStale(state.dailyTraining) && state.dailyTraining.isActive {
            state.activePage = .coach; return
        }
        let digest = ensureCoachDigestCurrent()
        let rounds = buildCoachTrainingRounds(digest)
        guard !rounds.isEmpty else { toast = "今日训练题暂时不可用"; state.toastMessage = toast; return }
        state.activePage = .coach
        state.input = ""
        state.coachInput = ""
        state.dailyTraining = DailyTrainingState(dateKey: digest.dateKey, rounds: rounds, currentIndex: 0, phase: .askingQuestion, currentQuestionText: "")
        state.toastMessage = "已开始今日训练 · 正在出第1题"
        toast = state.toastMessage
        persist()
        await launchDailyTrainingRound(rounds: rounds, roundIndex: 0)
    }

    func startCoachRecommendedTraining(_ question: CoachRecommendedQuestion) async {
        if state.isLoading { toast = "当前还有内容在生成，请稍等"; state.toastMessage = toast; return }
        let normalizedPrompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else { toast = "这道推荐题暂时不可用"; state.toastMessage = toast; return }
        let digest = ensureCoachDigestCurrent()
        let fallbackTitle: String = {
            if let p = digest.focusAreas.first?.point { return "\(p) · 典型题" }
            return "教练推荐题"
        }()
        let round = CoachRecommendedQuestion(
            id: question.id,
            title: question.title.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { fallbackTitle },
            reason: question.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: normalizedPrompt,
            basis: question.basis,
            anchorSavedQuestionId: question.anchorSavedQuestionId
        )
        state.activePage = .coach
        state.input = ""
        state.coachInput = ""
        state.dailyTraining = DailyTrainingState(dateKey: digest.dateKey, rounds: [round], currentIndex: 0, phase: .askingQuestion, currentQuestionText: "")
        state.toastMessage = "已开始针对性训练 · 正在出题"
        toast = state.toastMessage
        persist()
        await launchDailyTrainingRound(rounds: [round], roundIndex: 0)
    }

    /// 生成今日训练的第 roundIndex 题（流式），完成后进入 AWAITING_ANSWER
    private func launchDailyTrainingRound(rounds: [CoachRecommendedQuestion], roundIndex: Int) async {
        guard rounds.indices.contains(roundIndex) else {
            state.dailyTraining = DailyTrainingState(dateKey: currentCoachDateKey(), rounds: rounds, currentIndex: max(rounds.count - 1, 0), phase: .completed, currentQuestionText: "")
            state.toastMessage = "今日训练已完成 🎉"; toast = state.toastMessage; persist(); return
        }
        let round = rounds[roundIndex]
        requestToken += 1
        let token = requestToken
        let displayText = buildTrainingRoundDisplayText(round: round, roundIndex: roundIndex, totalRounds: rounds.count)
        let displayUser = CoachChatMessage(id: nextMessageId(), role: .user, time: nowTimeString(), text: displayText)
        let assistantId = nextMessageId()
        let assistantTime = nowTimeString()
        let placeholder = CoachChatMessage(id: assistantId, role: .assistant, time: assistantTime, text: "正在生成第\(roundIndex + 1)题...")
        state.coachMessages = upsertCoachMessage(state.coachMessages, target: displayUser)
        state.coachMessages = upsertCoachMessage(state.coachMessages, target: placeholder)
        state.dailyTraining.phase = .askingQuestion
        state.dailyTraining.currentQuestionText = ""
        persist()
        trainingBuffer = ""
        let config = state.settings.toArkRuntimeConfig()
        let result = await arkClient.generateReplyStream(messages: [ArkRequestMessage(role: "user", text: round.prompt)], config: config, onDelta: { [weak self] delta in
            Task { @MainActor in
                guard let self = self else { return }
                self.trainingBuffer += delta
                let partial = self.trainingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "正在生成第\(roundIndex + 1)题..." : self.trainingBuffer
                let partialMsg = CoachChatMessage(id: assistantId, role: .assistant, time: assistantTime, text: partial)
                self.state.coachMessages = upsertCoachMessage(self.state.coachMessages, target: partialMsg)
            }
        })
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] reply in Task { @MainActor in
                guard let self = self else { return }
                let resolved = reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? self.trainingBuffer.trimmingCharacters(in: .whitespacesAndNewlines) : reply
                let msg = CoachChatMessage(id: assistantId, role: .assistant, time: assistantTime, text: resolved.isEmpty ? "（题目生成失败，请重试）" : resolved)
                self.state.coachMessages = upsertCoachMessage(self.state.coachMessages, target: msg)
                self.state.dailyTraining.phase = .awaitingAnswer
                self.state.dailyTraining.currentQuestionText = resolved
                self.state.toastMessage = "第\(roundIndex + 1)题已准备好，直接作答"
                self.toast = self.state.toastMessage
                self.trainingBuffer = ""
                self.persist()
            }},
            onFailure: { [weak self] error in Task { @MainActor in
                guard let self = self else { return }
                self.state.coachMessages = self.state.coachMessages.filter { $0.id != assistantId }
                self.state.dailyTraining = DailyTrainingState()
                self.handleFailure(error)
            }}
        )
    }

    /// 提交训练作答：批改并进入下一轮或完成
    func submitDailyTrainingAnswer(_ answer: String, fromCoachInput: Bool = false) async {
        let training = state.dailyTraining
        if isDailyTrainingStale(training) {
            state.dailyTraining = DailyTrainingState()
            state.toastMessage = "今日训练已过期，请重新开始"; toast = state.toastMessage; persist(); return
        }
        guard training.phase == .awaitingAnswer, let round = training.currentRound else { return }
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let userAnswer = CoachChatMessage(id: nextMessageId(), role: .user, time: nowTimeString(), text: normalized)
        state.coachMessages = upsertCoachMessage(state.coachMessages, target: userAnswer)
        if fromCoachInput { state.coachInput = "" }
        let assistantId = nextMessageId()
        let assistantTime = nowTimeString()
        let placeholder = CoachChatMessage(id: assistantId, role: .assistant, time: assistantTime, text: "正在批改...")
        state.coachMessages = upsertCoachMessage(state.coachMessages, target: placeholder)
        state.dailyTraining.phase = .reviewingAnswer
        persist()
        let evalPrompt = buildTrainingEvaluationPrompt(round: round, trainingQuestion: training.currentQuestionText, studentAnswer: normalized)
        requestToken += 1
        let token = requestToken
        trainingBuffer = ""
        let config = state.settings.toArkRuntimeConfig()
        let result = await arkClient.generateReplyStream(messages: [ArkRequestMessage(role: "user", text: evalPrompt)], config: config, onDelta: { [weak self] delta in
            Task { @MainActor in
                guard let self = self else { return }
                self.trainingBuffer += delta
                let partial = self.trainingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "正在批改..." : self.trainingBuffer
                let partialMsg = CoachChatMessage(id: assistantId, role: .assistant, time: assistantTime, text: partial)
                self.state.coachMessages = upsertCoachMessage(self.state.coachMessages, target: partialMsg)
            }
        })
        deliverTokenAwareResult(result, requestToken: token, activeToken: requestToken,
            onStale: { },
            onSuccess: { [weak self] reply in Task { @MainActor in
                guard let self = self else { return }
                let resolved = reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? self.trainingBuffer.trimmingCharacters(in: .whitespacesAndNewlines) : reply
                let msg = CoachChatMessage(id: assistantId, role: .assistant, time: assistantTime, text: resolved.isEmpty ? "（批改失败）" : resolved)
                self.state.coachMessages = upsertCoachMessage(self.state.coachMessages, target: msg)
                self.trainingBuffer = ""
                let nextIndex = self.state.dailyTraining.currentIndex + 1
                if nextIndex >= self.state.dailyTraining.rounds.count {
                    self.state.dailyTraining.phase = .completed
                    self.state.toastMessage = "今日训练已完成 🎉"; self.toast = self.state.toastMessage
                    self.persist()
                } else {
                    self.state.dailyTraining.currentIndex = nextIndex
                    self.state.toastMessage = "进入第\(nextIndex + 1)题"; self.toast = self.state.toastMessage
                    self.persist()
                    await self.launchDailyTrainingRound(rounds: self.state.dailyTraining.rounds, roundIndex: nextIndex)
                }
            }},
            onFailure: { [weak self] error in Task { @MainActor in
                guard let self = self else { return }
                self.state.coachMessages = self.state.coachMessages.filter { $0.id != assistantId }
                self.state.dailyTraining.phase = .awaitingAnswer
                self.handleFailure(error)
            }}
        )
    }

    func reviewAnkiCard(_ card: AnkiCard, mastery: CardMasteryLevel) {
        guard let index = state.ankiCards.firstIndex(where: { $0.id == card.id }) else { return }
        let reviewed = applySrsReview(card, mastery: mastery)
        var updatedCards = state.ankiCards
        updatedCards[index] = reviewed
        // 卡组专练模式下记录选择，并在练完时弹出汇总
        let normalizedDeck = state.focusedDeckName
        var selections = state.deckPracticeSelections
        var showSummary = state.showDeckPracticeSummary
        if let deck = normalizedDeck, (normalizeDeckName(card.deckName) ?? DEFAULT_ANKI_DECK_NAME) == deck {
            selections[card.id] = mastery
            let deckTotal = updatedCards.filter { (normalizeDeckName($0.deckName) ?? DEFAULT_ANKI_DECK_NAME) == deck }.count
            showSummary = deckTotal > 0 && selections.count >= deckTotal
        }
        state.ankiCards = sortAnkiCardsForReview(updatedCards)
        state.deckPracticeSelections = selections
        state.showDeckPracticeSummary = showSummary
        state.toastMessage = "已标记\(mastery.label)，下次复习 \(formatSessionTime(reviewed.nextReviewAt))"
        toast = state.toastMessage
        globalAnkiCards = mergeGlobalAnkiCards(registry.orderedSessions() + [toStoredSessionSnapshot(state: state, title: buildSessionTitle(state.messages, fallbackTime: nowTimeString()), createdAt: currentTimeMillis(), updatedAt: currentTimeMillis())])
        persist()
    }

    // MARK: - Anki 卡组练习模式

    // 卡组重命名 / 卡片编辑的弹窗状态
    @Published var editingAnkiCardId: String? = nil
    @Published var showRenameDeckDialog: Bool = false
    @Published var renameDeckPrompt: String = ""
    @Published var renameDeckNewName: String = ""

    func beginEditAnkiCard(_ card: AnkiCard) { editingAnkiCardId = card.id }
    func cancelEditAnkiCard() { editingAnkiCardId = nil }

    func openDueReviewQueue() {
        let dueCount = countDueReviewCards(state.ankiCards)
        guard dueCount > 0 else { toast = "今日暂无待复习"; state.toastMessage = toast; return }
        state.activePage = .anki
        state.isDueReviewMode = true
        state.focusedDeckName = nil
        state.toastMessage = "进入今日待复习（\(dueCount) 张）"
        toast = state.toastMessage
        persist()
    }

    func openDeckFocusedPractice(deckName: String) {
        guard let normalized = normalizeDeckName(deckName), !normalized.isEmpty else {
            toast = "卡组名称无效"; state.toastMessage = toast; return
        }
        let target = state.ankiCards.filter { (normalizeDeckName($0.deckName) ?? DEFAULT_ANKI_DECK_NAME) == normalized }
        guard !target.isEmpty else { toast = "该卡组暂无可练习卡片"; state.toastMessage = toast; return }
        state.activePage = .anki
        state.isDueReviewMode = false
        state.focusedDeckName = normalized
        state.deckPracticeSelections = [:]
        state.showDeckPracticeSummary = false
        state.toastMessage = "进入卡组专练：\(normalized)"
        toast = state.toastMessage
        persist()
    }

    func closeDueReviewMode() {
        guard state.isDueReviewMode else { return }
        state.isDueReviewMode = false
        state.focusedDeckName = nil
    }

    func closeDeckFocusedPractice() {
        guard state.focusedDeckName != nil else { return }
        state.focusedDeckName = nil
        state.deckPracticeSelections = [:]
        state.showDeckPracticeSummary = false
    }

    func openDeckPracticeSummary() {
        guard state.focusedDeckName != nil else { return }
        state.showDeckPracticeSummary = true
    }

    func dismissDeckPracticeSummary() {
        guard state.showDeckPracticeSummary else { return }
        state.showDeckPracticeSummary = false
    }

    func restartDeckPracticeRound() {
        guard state.focusedDeckName != nil else { return }
        state.deckPracticeSelections = [:]
        state.showDeckPracticeSummary = false
        state.toastMessage = "已开始新一轮卡组专练"
        toast = state.toastMessage
    }

    /// 当前卡组专练的汇总（用于弹窗展示）
    var currentDeckPracticeSummary: DeckPracticeSummary? {
        guard let deck = state.focusedDeckName else { return nil }
        let cards = state.ankiCards.filter { (normalizeDeckName($0.deckName) ?? DEFAULT_ANKI_DECK_NAME) == deck }
        return buildDeckPracticeSummary(deckName: deck, cards: cards, selections: state.deckPracticeSelections)
    }

    // MARK: - Anki 卡片管理

    func updateAnkiCard(cardId: String, front: String, back: String, tags: [String]) {
        let normalizedFront = normalizeCardText(front, maxLen: 500)
        let normalizedBack = normalizeCardText(back, maxLen: 1200)
        let normalizedTags = filterToHighSchoolKnowledgeTags(tags, maxSize: 10)
        guard !normalizedFront.isEmpty, !normalizedBack.isEmpty else {
            toast = "题面和答案都不能为空"; state.toastMessage = toast; return
        }
        guard let index = state.ankiCards.firstIndex(where: { $0.id == cardId }) else {
            toast = "卡片不存在"; state.toastMessage = toast; return
        }
        var updatedCards = state.ankiCards
        let card = updatedCards[index]
        // front/back 为 let，整体重建卡片
        updatedCards[index] = AnkiCard(
            id: card.id,
            front: normalizedFront,
            back: normalizedBack,
            tags: normalizedTags,
            source: card.source,
            createdAt: card.createdAt,
            nextReviewAt: card.nextReviewAt,
            reviewCount: card.reviewCount,
            lastReviewedAt: card.lastReviewedAt,
            mastery: card.mastery,
            deckName: card.deckName
        )
        state.ankiCards = sortAnkiCardsForReview(updatedCards)
        state.toastMessage = "Anki 卡片已更新"
        toast = state.toastMessage
        persist()
    }

    func renameAnkiDeck(deckName: String, newDeckName: String) {
        let from = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        var to = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        to = String(to.prefix(12))
        guard !from.isEmpty, !to.isEmpty else { toast = "卡组名不能为空"; state.toastMessage = toast; return }
        guard from != DEFAULT_ANKI_DECK_NAME else { toast = "系统卡组不可重命名"; state.toastMessage = toast; return }
        guard from != to else { toast = "卡组名未变化"; state.toastMessage = toast; return }
        let updated = state.ankiCards.map { card -> AnkiCard in
            var c = card
            if c.deckName == from { c.deckName = to }
            return c
        }
        guard updated != state.ankiCards else { toast = "卡组不存在"; state.toastMessage = toast; return }
        state.ankiCards = sortAnkiCardsForReview(updated)
        state.toastMessage = "已重命名卡组"
        toast = state.toastMessage
        persist()
    }

    func archiveAnkiDeck(deckName: String) {
        let deck = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deck.isEmpty, deck != DEFAULT_ANKI_DECK_NAME else { return }
        let updated = state.ankiCards.map { card -> AnkiCard in
            var c = card
            if c.deckName == deck { c.deckName = DEFAULT_ANKI_DECK_NAME }
            return c
        }
        guard updated != state.ankiCards else { toast = "卡组不存在"; state.toastMessage = toast; return }
        state.ankiCards = sortAnkiCardsForReview(updated)
        state.toastMessage = "已归档到未分类"
        toast = state.toastMessage
        persist()
    }

    func deleteAnkiCard(cardId: String) {
        let before = state.ankiCards.count
        state.ankiCards = state.ankiCards.filter { $0.id != cardId }
        guard state.ankiCards.count != before else { toast = "卡片不存在"; state.toastMessage = toast; return }
        state.toastMessage = "已删除 Anki 卡片"
        toast = state.toastMessage
        persist()
    }

    // MARK: - Settings

    func openSettings() { state.isSettingsOpen = true }
    func cancelSettings() { state.settingsDraft = state.settings; state.isSettingsOpen = false }
    func saveSettings() { state.settings = state.settingsDraft; state.isSettingsOpen = false; persist() }

    // 恢复设置草稿为内置默认（保留 ARK/OpenSpeech 默认值，清空自定义端点）
    func resetSettingsDraft() { state.settingsDraft = RuntimeSettings.defaults() }

    /// 用当前草稿配置发起一次轻量连通性测试（非流式，发一个 ping）
    @Published var connectionTestResult: String? = nil
    @Published var isTestingConnection = false

    func testConnection() async {
        // 仅支持 OpenAI 兼容自定义端点：三项必须齐备，否则直接给出明确提示
        guard state.settingsDraft.hasCompleteCustomModel() else {
            connectionTestResult = "❌ 请先填齐 Base URL、API Key、模型名"
            return
        }
        let config = state.settingsDraft.customModelConfigOrNull() ?? state.settingsDraft.toArkRuntimeConfig()
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

    // 一键从提供商拉取模型列表
    @Published var fetchedModels: [String] = []
    @Published var isFetchingModels = false
    @Published var fetchModelsError: String? = nil

    func fetchModels() async {
        guard state.settingsDraft.hasCompleteCustomModel() else {
            fetchModelsError = "请先填齐 Base URL 和 API Key"
            return
        }
        let config = state.settingsDraft.customModelConfigOrNull() ?? state.settingsDraft.toArkRuntimeConfig()
        isFetchingModels = true
        fetchModelsError = nil
        fetchedModels = []
        defer { isFetchingModels = false }
        let result = await arkClient.listModels(config: config)
        switch result {
        case .success(let models):
            fetchedModels = models
            if models.isEmpty { fetchModelsError = "未返回任何模型" }
        case .failure(let error):
            fetchModelsError = resolveErrorHint(error, fallback: "拉取失败")
        }
    }

    // 自定义学习阶段（学习画像）
    func updateProfileLevel(_ level: String) {
        let trimmed = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.profile.level = trimmed
        persist()
    }

    // MARK: - FlowStudy 配对与上传（对齐 Android pairFlowStudy / pushSessionsToFlowStudy）
    @Published var flowStudyPairCode = ""
    @Published var flowStudyBusy = false
    @Published var flowStudyMessage: String? = nil

    /// 保证 settings 里有 device_id（缺则生成并持久化）
    private func ensureFlowStudyDeviceId() -> RuntimeSettings {
        let existing = state.settings.flowStudyDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty { return state.settings }
        let generated = "artiflow_\(UUID().uuidString.lowercased())"
        var updated = state.settings
        updated.flowStudyDeviceId = generated
        state.settings = updated
        state.settingsDraft = updated
        persist()
        return updated
    }

    func pairFlowStudy() async {
        let code = flowStudyPairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { flowStudyMessage = "配对码为空"; return }
        flowStudyBusy = true
        flowStudyMessage = "FlowStudy 配对中..."
        defer { flowStudyBusy = false }
        let settings = ensureFlowStudyDeviceId()
        let result = await flowStudyClient.pairDevice(serverUrl: settings.flowStudyServerUrl, pairCode: code, deviceId: settings.flowStudyDeviceId)
        switch result {
        case .success(let resp):
            var updated = settings
            updated.flowStudyDeviceToken = resp.deviceToken
            state.settings = updated
            state.settingsDraft = updated
            flowStudyMessage = "配对成功"
            persist()
        case .failure(let err):
            flowStudyMessage = "配对失败：\(resolveErrorHint(err, fallback: "未知错误"))"
        }
    }

    func pushSessionsToFlowStudy() async {
        flowStudyBusy = true
        flowStudyMessage = "上传主界面中..."
        defer { flowStudyBusy = false }
        let settings = ensureFlowStudyDeviceId()
        if settings.flowStudyServerUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            flowStudyMessage = "FlowStudy 地址为空"; return
        }
        if settings.flowStudyDeviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            flowStudyMessage = "请先配对获取设备 token"; return
        }
        let active = registry.orderedSessions().first { $0.id == state.activeSessionId } ?? registry.orderedSessions().first
        guard let active = active else { flowStudyMessage = "没有可上传的主界面内容"; return }
        var stateCopy = state
        stateCopy.settings = settings
        guard let payload = buildPersistedSessionsPayload(state: stateCopy, sessions: [active]), !payload.sessions.isEmpty else {
            flowStudyMessage = "没有可上传的主界面内容"; return
        }
        let payloadJson = store.exportPayloadJson(payload)
        let result = await flowStudyClient.pushSessions(serverUrl: settings.flowStudyServerUrl, deviceToken: settings.flowStudyDeviceToken, deviceId: settings.flowStudyDeviceId, payloadJson: payloadJson)
        switch result {
        case .success(let resp):
            flowStudyMessage = "上传完成：+\(resp.insertedSessions) 更新\(resp.updatedSessions)"
            persist()
        case .failure(let err):
            flowStudyMessage = "上传失败：\(resolveErrorHint(err, fallback: "未知错误"))"
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
