import Foundation

struct StoredSession: Equatable {
    let id: String
    var title: String
    let createdAt: Int64
    var updatedAt: Int64
    var messages: [ChatMessage]
    var histories: [String: [SpanDetail]]
    var profile: ProfileState
    var input: String
    var coachInput: String
    var activePage: WorkspacePage
    var quickFollowupSpanId: String?
    var quickFollowupDetailId: String?
    var coachMessages: [CoachChatMessage]
    var coachDigest: CoachDailyDigest?
    var dailyTraining: DailyTrainingState
    var savedQuestions: [SavedQuestion]
    var knowledgePoints: [String: Int]
    var ankiCards: [AnkiCard]
}

struct PersistedSessions {
    let activeSessionId: String
    let settings: RuntimeSettings
    let sessions: [StoredSession]
}

// MARK: - Sanitization (StudyChatViewModelSupport.kt)

func sanitizeStoredSession(_ session: StoredSession) -> StoredSession {
    var copy = session
    copy.savedQuestions = session.savedQuestions.compactMap { sanitizeSavedQuestion($0) }
    copy.knowledgePoints = sanitizeKnowledgePointsMap(session.knowledgePoints)
    copy.ankiCards = sortAnkiCardsForReview(session.ankiCards.map { sanitizeAnkiCard($0) })
    return copy
}

func sanitizePersistedSessions(_ payload: PersistedSessions) -> PersistedSessions {
    return PersistedSessions(
        activeSessionId: payload.activeSessionId,
        settings: payload.settings,
        sessions: payload.sessions.map { sanitizeStoredSession($0) }
    )
}

// MARK: - Session helpers (StudyChatSessionHelpers.kt)

func buildIntroGuideContent() -> String {
    return [
        "你好，我是你的学习搭子。主界面里每个题目都独立回答，不共享上下文。",
        "每道题都会生成一组可滑动的回复段落；回复气泡最底下时间那一层也支持左滑交互。",
        "底部时间那一层左滑松手会直接进入本题追问；段落卡左滑松手会自动讲解；左滑后继续按住会进入语音追问。",
        "右滑松手会打开该卡片详解；右滑并停留会进入精细追问，当前题目的追问链会持续保留。"
    ].joined(separator: "\n\n")
}

func buildUiStateFromSession(session: StoredSession, ankiCards: [AnkiCard], settings: RuntimeSettings, toastMessage: String?) -> ChatUiState {
    let sanitizedSession = sanitizeStoredSession(session)
    let sanitizedCards = sortAnkiCardsForReview(ankiCards.map { sanitizeAnkiCard($0) })
    return ChatUiState(
        messages: sanitizedSession.messages,
        histories: sanitizedSession.histories,
        profile: sanitizedSession.profile,
        input: sanitizedSession.input,
        coachInput: sanitizedSession.coachInput,
        selectedSpanId: nil,
        selectedDetailId: nil,
        quickFollowupSpanId: sanitizedSession.quickFollowupSpanId,
        quickFollowupDetailId: sanitizedSession.quickFollowupDetailId,
        archiveFocusSavedQuestionId: nil,
        activePage: sanitizedSession.activePage,
        coachMessages: sanitizedSession.coachMessages,
        coachDigest: sanitizedSession.coachDigest,
        dailyTraining: sanitizedSession.dailyTraining,
        savedQuestions: sanitizedSession.savedQuestions,
        knowledgePoints: sanitizedSession.knowledgePoints,
        ankiCards: sanitizedCards,
        activeSessionId: sanitizedSession.id,
        toastMessage: toastMessage,
        processingSpanIds: [],
        isLoading: false,
        isSettingsOpen: false,
        settings: settings,
        settingsDraft: settings
    )
}

func toStoredSessionSnapshot(state: ChatUiState, title: String, createdAt: Int64, updatedAt: Int64) -> StoredSession {
    return sanitizeStoredSession(StoredSession(
        id: state.activeSessionId,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        messages: state.messages,
        histories: state.histories,
        profile: state.profile,
        input: state.input,
        coachInput: state.coachInput,
        activePage: state.activePage,
        quickFollowupSpanId: state.quickFollowupSpanId,
        quickFollowupDetailId: state.quickFollowupDetailId,
        coachMessages: state.coachMessages,
        coachDigest: state.coachDigest,
        dailyTraining: state.dailyTraining,
        savedQuestions: state.savedQuestions,
        knowledgePoints: state.knowledgePoints,
        ankiCards: state.ankiCards
    ))
}

func buildSyncedSessionSnapshot(state: ChatUiState, fallbackTime: String, now: Int64, existingCreatedAt: Int64?) -> StoredSession {
    return toStoredSessionSnapshot(
        state: state,
        title: buildSessionTitle(state.messages, fallbackTime: fallbackTime),
        createdAt: existingCreatedAt ?? now,
        updatedAt: now
    )
}

func buildPersistedSessionsPayload(state: ChatUiState, sessions: [StoredSession]) -> PersistedSessions? {
    let activeSessionId = state.activeSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    if activeSessionId.isEmpty { return nil }
    return sanitizePersistedSessions(PersistedSessions(
        activeSessionId: activeSessionId,
        settings: state.settings,
        sessions: sessions
    ))
}

func createInitialSessionState(
    sessionId: String,
    introMessage: ChatMessage,
    ankiCards: [AnkiCard],
    settings: RuntimeSettings,
    settingsDraft: RuntimeSettings,
    showIntroToast: Bool
) -> ChatUiState {
    return ChatUiState(
        messages: [introMessage],
        histories: [:],
        profile: ProfileState(level: "高二 · 进阶冲刺"),
        input: "",
        coachInput: "",
        selectedSpanId: nil,
        selectedDetailId: nil,
        quickFollowupSpanId: nil,
        quickFollowupDetailId: nil,
        archiveFocusSavedQuestionId: nil,
        activePage: .chat,
        coachMessages: [],
        coachDigest: nil,
        dailyTraining: DailyTrainingState(),
        savedQuestions: [],
        knowledgePoints: [:],
        ankiCards: sortAnkiCardsForReview(ankiCards),
        activeSessionId: sessionId,
        toastMessage: showIntroToast ? "已开始新对话" : nil,
        processingSpanIds: [],
        isLoading: false,
        isSettingsOpen: false,
        settings: settings,
        settingsDraft: settingsDraft
    )
}

// MARK: - Session registry (StudyChatSessionRegistry.kt)

final class SessionRegistry {
    private var sessionsById: [String: StoredSession] = [:]
    private var sessionOrder: [String] = []

    func get(_ id: String) -> StoredSession? {
        return sessionsById[id]
    }

    func put(_ session: StoredSession, moveToFront: Bool) {
        sessionsById[session.id] = session
        if moveToFront {
            touch(session.id)
        } else if !sessionOrder.contains(session.id) {
            sessionOrder.append(session.id)
        }
    }

    func replaceAll(_ sessions: [StoredSession]) {
        clear()
        for session in sessions {
            put(session, moveToFront: false)
        }
    }

    @discardableResult
    func remove(_ id: String) -> StoredSession? {
        sessionOrder.removeAll { $0 == id }
        return sessionsById.removeValue(forKey: id)
    }

    func clear() {
        sessionsById.removeAll()
        sessionOrder.removeAll()
    }

    func touch(_ id: String) {
        sessionOrder.removeAll { $0 == id }
        sessionOrder.insert(id, at: 0)
    }

    func isEmpty() -> Bool {
        return sessionsById.isEmpty
    }

    func contains(_ id: String) -> Bool {
        return sessionsById[id] != nil
    }

    func firstIdOrNull() -> String? {
        if let first = sessionOrder.first { return first }
        return sessionsById.keys.first
    }

    func createdAtOf(_ id: String) -> Int64? {
        return sessionsById[id]?.createdAt
    }

    func orderedSessions() -> [StoredSession] {
        return sessionOrder.compactMap { sessionsById[$0] }
    }
}
