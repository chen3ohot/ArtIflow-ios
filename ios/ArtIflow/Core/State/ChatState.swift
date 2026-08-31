import Foundation

struct ChatUiState: Equatable {
    var messages: [ChatMessage] = []
    var histories: [String: [SpanDetail]] = [:]
    var profile: ProfileState = ProfileState(level: "高二 · 进阶冲刺")
    var input: String = ""
    var coachInput: String = ""
    var selectedSpanId: String? = nil
    var selectedDetailId: String? = nil
    var quickFollowupSpanId: String? = nil
    var quickFollowupDetailId: String? = nil
    var archiveFocusSavedQuestionId: String? = nil
    var activePage: WorkspacePage = .chat
    var coachMessages: [CoachChatMessage] = []
    var coachDigest: CoachDailyDigest? = nil
    var dailyTraining: DailyTrainingState = DailyTrainingState()
    var savedQuestions: [SavedQuestion] = []
    var knowledgePoints: [String: Int] = [:]
    var ankiCards: [AnkiCard] = []
    var isDueReviewMode: Bool = false
    var focusedDeckName: String? = nil
    var deckPracticeSelections: [String: CardMasteryLevel] = [:]
    var showDeckPracticeSummary: Bool = false
    var activeSessionId: String = ""
    var toastMessage: String? = nil
    var processingSpanIds: Set<String> = []
    var isLoading: Bool = false
    var isSettingsOpen: Bool = false
    var settings: RuntimeSettings
    var settingsDraft: RuntimeSettings

    static func defaults() -> RuntimeSettings {
        return RuntimeSettings.defaults()
    }
}

// MARK: - State reducers (StudyChatStateReducers.kt)

func queueImageQuestionState(current: ChatUiState, userMessage: ChatMessage, question: String, source: String) -> ChatUiState {
    var next = current
    next.messages.append(userMessage)
    next.profile = current.profile.updateWith(text: question, isFollowup: false, isVoice: false)
    // 图片提问用 question 提取知识点（source 多为通用“拍照搜题”提示词，无法命中知识点）
    next.knowledgePoints = mergeKnowledgePoints(current.knowledgePoints, texts: [question])
    return next
}

func queueQuestionState(current: ChatUiState, userMessage: ChatMessage, question: String, isFollowup: Bool, isVoice: Bool, clearInput: Bool) -> ChatUiState {
    var next = current
    if clearInput { next.input = "" }
    next.messages.append(userMessage)
    next.profile = current.profile.updateWith(text: question, isFollowup: isFollowup, isVoice: isVoice)
    next.knowledgePoints = mergeKnowledgePoints(current.knowledgePoints, texts: [question])
    return next
}

func queueSpanFollowupState(current: ChatUiState, spanId: String, question: String, isVoice: Bool, clearInput: Bool = false) -> ChatUiState {
    var next = current
    if clearInput { next.input = "" }
    next.profile = current.profile.updateWith(text: question, isFollowup: true, isVoice: isVoice)
    next.knowledgePoints = mergeKnowledgePoints(current.knowledgePoints, texts: [question])
    return markSpanProcessing(next, spanId: spanId)
}

func appendAssistantMessageState(current: ChatUiState, assistantMessage: ChatMessage, toastMessage: String?, knowledgeTexts: [String] = []) -> ChatUiState {
    var next = current
    next.messages = upsertAssistantMessage(current.messages, assistantMessage: assistantMessage)
    if knowledgeTexts.isEmpty {
        next.knowledgePoints = current.knowledgePoints
    } else {
        next.knowledgePoints = mergeKnowledgePoints(current.knowledgePoints, texts: knowledgeTexts)
    }
    next.toastMessage = toastMessage
    return next
}

func upsertAssistantMessageState(current: ChatUiState, assistantMessage: ChatMessage) -> ChatUiState {
    var next = current
    next.messages = upsertAssistantMessage(current.messages, assistantMessage: assistantMessage)
    return next
}

private func upsertAssistantMessage(_ messages: [ChatMessage], assistantMessage: ChatMessage) -> [ChatMessage] {
    if let index = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
        var mutable = messages
        mutable[index] = assistantMessage
        return mutable
    }
    return messages + [assistantMessage]
}

func rollbackQueuedUserMessageState(current: ChatUiState, messageId: String, restoredInput: String? = nil, toastMessage: String? = nil) -> ChatUiState {
    var next = current
    next.messages = current.messages.filter { $0.id != messageId }
    if let restored = restoredInput, !restored.isEmpty, current.input.isEmpty {
        next.input = restored
    } else {
        next.input = current.input
    }
    next.toastMessage = toastMessage
    return next
}

// MARK: - Span processing helpers (StudyChatViewModelSupport.kt)

func markSpanProcessing(_ current: ChatUiState, spanId: String) -> ChatUiState {
    var next = current
    next.processingSpanIds.insert(spanId)
    return next
}

func clearSpanProcessing(_ current: ChatUiState, spanId: String, toastMessage: String? = nil) -> ChatUiState {
    var next = current
    next.processingSpanIds.remove(spanId)
    next.toastMessage = toastMessage
    return next
}

func appendSpanDetailHistory(current: ChatUiState, spanId: String, detail: SpanDetail, toastMessage: String) -> ChatUiState {
    var next = current
    var histories = current.histories
    let existing = current.histories[spanId] ?? []
    histories[spanId] = [detail] + existing
    next.histories = histories
    next.processingSpanIds.remove(spanId)
    next.toastMessage = toastMessage
    return next
}

func upsertSpanDetailHistory(current: ChatUiState, spanId: String, detail: SpanDetail, clearProcessing: Bool = false, toastMessage: String? = nil) -> ChatUiState {
    var next = current
    var histories = current.histories
    let existing = current.histories[spanId] ?? []
    if let index = existing.firstIndex(where: { $0.id == detail.id }) {
        var mutable = existing
        mutable[index] = detail
        histories[spanId] = mutable
    } else {
        histories[spanId] = [detail] + existing
    }
    next.histories = histories
    if clearProcessing { next.processingSpanIds.remove(spanId) }
    next.toastMessage = toastMessage
    return next
}

func removeSpanDetailHistory(current: ChatUiState, spanId: String, detailId: String) -> ChatUiState {
    let existing = current.histories[spanId] ?? []
    if !existing.contains(where: { $0.id == detailId }) { return current }
    var next = current
    var histories = current.histories
    let remaining = existing.filter { $0.id != detailId }
    if remaining.isEmpty {
        histories.removeValue(forKey: spanId)
    } else {
        histories[spanId] = remaining
    }
    next.histories = histories
    return next
}
