import Foundation

// MARK: - Mistake domain (data/MistakeModels.kt)

enum MistakeType: String {
    case conceptError = "CONCEPT_ERROR"
    case calculationError = "CALCULATION_ERROR"
    case readingError = "READING_ERROR"
    case methodError = "METHOD_ERROR"
}

struct MistakeAnalysis {
    let rootCause: String
    let suggestions: [String]
    let relatedConcepts: [String]
}

struct QuestionTags {
    let difficulty: String
    let importance: String
    let frequency: String
}

struct MistakeQuestion {
    let id: String
    let questionImage: String?
    let questionText: String
    let subject: String
    let knowledgePoints: [String]
    let questionType: String
    let mistakeType: MistakeType
    let mistakeReason: String
    let correctAnswer: String
    let studentAnswer: String
    let aiAnalysis: MistakeAnalysis?
    let createdAt: Int64
    let reviewedAt: Int64?
    let masteryLevel: Int
    let reviewCount: Int
    let nextReviewAt: Int64?
}

enum GroupByType {
    case bySubject, byMistakeType, byDate, byMastery
}

enum ExportFormat {
    case pdf, excel, markdown, json
}

// MARK: - Image payload

struct ImagePayload {
    let bytes: Data
    let mimeType: String
}

// MARK: - ARK runtime config

struct ArkRuntimeConfig {
    var apiKey: String
    var model: String
    var baseUrl: String
    var endpoint: String
    var systemPrompt: String
}

struct ArkRequestMessage: Equatable {
    let role: String
    let text: String
}

// MARK: - Chat models (ui/StudyChatModels.kt)

enum WorkspacePage: String {
    case chat = "CHAT"
    case quickFollowup = "QUICK_FOLLOWUP"
    case coach = "COACH"
    case archive = "ARCHIVE"
    case anki = "ANKI"
    case profile = "PROFILE"

    static func from(_ raw: String) -> WorkspacePage {
        return WorkspacePage(rawValue: raw) ?? .chat
    }
}

enum KnowledgeGapLevel: String {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"

    var label: String {
        switch self {
        case .high: return "优先补"
        case .medium: return "建议补"
        case .low: return "继续看"
        }
    }

    static func from(_ raw: String) -> KnowledgeGapLevel {
        return KnowledgeGapLevel(rawValue: raw) ?? .medium
    }
}

enum CoachMessageRole: String {
    case user = "USER"
    case assistant = "ASSISTANT"

    static func from(_ raw: String) -> CoachMessageRole {
        return CoachMessageRole(rawValue: raw) ?? .assistant
    }
}

enum DailyTrainingPhase: String {
    case idle = "IDLE"
    case askingQuestion = "ASKING_QUESTION"
    case awaitingAnswer = "AWAITING_ANSWER"
    case reviewingAnswer = "REVIEWING_ANSWER"
    case completed = "COMPLETED"

    static func from(_ raw: String) -> DailyTrainingPhase {
        return DailyTrainingPhase(rawValue: raw) ?? .idle
    }
}

enum CardMasteryLevel: String {
    case unrated = "UNRATED"
    case needsWork = "NEEDS_WORK"
    case familiar = "FAMILIAR"
    case proficient = "PROFICIENT"

    var label: String {
        switch self {
        case .unrated: return "未标记"
        case .needsWork: return "生疏"
        case .familiar: return "一般"
        case .proficient: return "熟练"
        }
    }

    var reviewPriority: Int {
        switch self {
        case .unrated: return 0
        case .needsWork: return 1
        case .familiar: return 2
        case .proficient: return 3
        }
    }

    static func from(_ raw: String) -> CardMasteryLevel {
        return CardMasteryLevel(rawValue: raw) ?? .unrated
    }
}

struct ModelPreset: Equatable {
    let id: String
    let name: String
    let baseUrl: String
    let apiKey: String
    let modelName: String
}

struct RuntimeSettings: Equatable {
    var arkApiKey: String
    var arkModel: String
    var arkBaseUrl: String
    var arkEndpoint: String
    var arkSystemPrompt: String
    var imagePrompt: String
    var openSpeechApiKey: String
    var openSpeechResourceId: String
    var openSpeechSubmitUrl: String
    var openSpeechQueryUrl: String
    var openSpeechUid: String
    var flowStudyServerUrl: String
    var flowStudyDeviceId: String
    var flowStudyDeviceToken: String
    var customModelBaseUrl: String = ""
    var customModelApiKey: String = ""
    var customModelName: String = ""
    var customModelPresets: [ModelPreset] = []
}

struct ProfileState: Equatable {
    var level: String
    var topicHits: [String: Int] = [:]
    var followups: Int = 0
    var voiceFollowups: Int = 0
}

struct SpanData: Equatable {
    let id: String
    let content: String
    let sourceQuestion: String
    var detailId: String? = nil
}

struct SpanDetail: Equatable {
    let id: String
    let mode: String
    let time: String
    let question: String?
    let answer: String
    let parentDetailId: String?
    let summary: String?
}

enum ChatMessage: Equatable {
    case user(id: String, time: String, text: String, imagePreviewBytes: Data? = nil, imagePreviewList: [Data] = [])
    case assistant(id: String, time: String, spans: [SpanData], mainSpan: SpanData? = nil, reasoningSummary: String? = nil)

    var id: String {
        switch self {
        case .user(let id, _, _, _, _): return id
        case .assistant(let id, _, _, _, _): return id
        }
    }

    var time: String {
        switch self {
        case .user(_, let time, _, _, _): return time
        case .assistant(_, let time, _, _, _): return time
        }
    }
}

extension ChatMessage {
    func findSpan(_ spanId: String?) -> SpanData? {
        guard case .assistant(_, _, let spans, let mainSpan, _) = self, let spanId = spanId, !spanId.isEmpty else {
            return nil
        }
        if let mainSpan = mainSpan, mainSpan.id == spanId { return mainSpan }
        return spans.first { $0.id == spanId }
    }

    func interactiveSpans() -> [SpanData] {
        guard case .assistant(_, _, let spans, let mainSpan, _) = self else { return [] }
        var result: [SpanData] = []
        if let mainSpan = mainSpan { result.append(mainSpan) }
        result.append(contentsOf: spans)
        return result
    }

    func fullAnswerText() -> String {
        guard case .assistant(_, _, let spans, let mainSpan, _) = self else { return "" }
        let normalizedMain = (mainSpan?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedMain.isEmpty { return normalizedMain }
        return spans
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SavedQuestion: Equatable {
    let id: String
    let sourceMessageId: String
    let question: String
    let answer: String
    let sourceTime: String
    let savedAt: Int64
    var followupCount: Int = 0
    var knowledgeTags: [String] = []
    var subject: String = ""
    var questionType: String = ""
    var analysisSummary: String = ""
    var imagePreviewBytes: Data? = nil
    var imagePreviewList: [Data] = []
}

struct AnkiCard: Equatable {
    let id: String
    let front: String
    let back: String
    var tags: [String]
    let source: String
    let createdAt: Int64
    var nextReviewAt: Int64
    var reviewCount: Int
    var lastReviewedAt: Int64?
    var mastery: CardMasteryLevel
    var deckName: String

    init(
        id: String,
        front: String,
        back: String,
        tags: [String],
        source: String,
        createdAt: Int64,
        nextReviewAt: Int64? = nil,
        reviewCount: Int = 0,
        lastReviewedAt: Int64? = nil,
        mastery: CardMasteryLevel = .unrated,
        deckName: String = DEFAULT_ANKI_DECK_NAME
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.tags = tags
        self.source = source
        self.createdAt = createdAt
        self.nextReviewAt = nextReviewAt ?? createdAt
        self.reviewCount = reviewCount
        self.lastReviewedAt = lastReviewedAt
        self.mastery = mastery
        self.deckName = deckName
    }
}

struct CoachChatMessage: Equatable {
    let id: String
    let role: CoachMessageRole
    let time: String
    let text: String
}

struct CoachFocusArea: Equatable {
    let point: String
    let level: KnowledgeGapLevel
    let diagnosis: String
    let action: String
    let evidence: String
}

struct CoachRecommendedQuestion: Equatable {
    let id: String
    let title: String
    let reason: String
    let prompt: String
    let basis: String
    let anchorSavedQuestionId: String?
}

struct CoachDailyDigest: Equatable {
    let dateKey: String
    let generatedAt: Int64
    let headline: String
    let summary: String
    let focusAreas: [CoachFocusArea]
    let recommendedQuestions: [CoachRecommendedQuestion]
}

struct DailyTrainingState: Equatable {
    var dateKey: String = ""
    var rounds: [CoachRecommendedQuestion] = []
    var currentIndex: Int = 0
    var phase: DailyTrainingPhase = .idle
    var currentQuestionText: String = ""

    var isActive: Bool {
        return !rounds.isEmpty && phase != .idle && phase != .completed
    }

    var totalRounds: Int { return rounds.count }

    var currentRound: CoachRecommendedQuestion? {
        let index = max(0, currentIndex)
        guard index < rounds.count else { return nil }
        return rounds[index]
    }
}

struct KnowledgeGapInsight {
    let point: String
    let level: KnowledgeGapLevel
    let score: Int
    let evidence: String
    let diagnosis: String
    let action: String
}

struct FollowupTreeScope {
    let spanId: String
    let spanContent: String
    let sourceQuestion: String
    let details: [SpanDetail]
}

struct DeckPracticeSummary {
    let deckName: String
    let totalCards: Int
    let reviewedCards: Int
    let needsWorkCount: Int
    let familiarCount: Int
    let proficientCount: Int
}

struct AnkiDeckSummary {
    let name: String
    let cardCount: Int
    let topTags: [String]
    let needsWorkCount: Int
    let proficientCount: Int
}

struct AiAnkiCardPayload {
    let front: String
    let back: String
    let tags: [String]
    let deck: String?
}

struct ImageQuestionArchivePayload {
    let question: String
    let subject: String
    let questionType: String
    let knowledgeTags: [String]
    let analysisSummary: String
}

struct SessionSeeds {
    var messageSeed: Int
    var spanSeed: Int
    var detailSeed: Int
    var cardSeed: Int
}

// MARK: - Default constants

let DEFAULT_ARK_MODEL = "doubao-seed-2-0-pro-260215"
let DEFAULT_ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"
let DEFAULT_ARK_ENDPOINT = "responses"
let DEFAULT_ARK_SYSTEM_PROMPT = "你是中学学习辅导助手。回答简洁明了：先给结论，再给关键点；默认3-6行；不要套话，不要长篇大论。"
let DEFAULT_OPENSPEECH_RESOURCE_ID = "volc.seedasr.auc"
let DEFAULT_OPENSPEECH_SUBMIT_URL = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit"
let DEFAULT_OPENSPEECH_QUERY_URL = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/query"
let DEFAULT_OPENSPEECH_UID = "豆包语音"
let DEFAULT_IMAGE_PROMPT = "你是一名中学学科辅导老师。请识别题目并简洁作答：先给结论，再给2-4条必要步骤；多小题按编号回答；不要套话和长篇大论。"
let ANKI_CARD_SYSTEM_PROMPT = "你是Anki制卡助手。根据学习交互自选最合适卡型，输出可直接测验的卡片；内容简洁准确，不套模板。"
let DEFAULT_ANKI_DECK_NAME = "未分类"
let COACH_SYSTEM_PROMPT = "你是学生的AI学习教练。回答时先指出最核心的问题，再给1-3条可执行建议；语言直接、具体、简短，不空话。必要时可以安排一题小练习或判断标准。"
let LEGACY_ARK_SYSTEM_PROMPT = "你是一个有用的AI学习辅导助手，擅长把复杂知识点讲清楚，优先给步骤化解释。"
let LEGACY_ARK_MODEL = "doubao-seed-1-8-251228"
let LEGACY_IMAGE_PROMPT = "你是一名中学学科辅导老师。请先识别图片中的题干，再按步骤讲解并给出最终答案。如果图片里有多个小题，请按小题编号分别作答。输出格式：\n1) 题目识别\n2) 解题思路\n3) 详细步骤\n4) 最终答案"
let MILLIS_PER_DAY: Int64 = 24 * 60 * 60 * 1000
