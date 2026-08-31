import Foundation

// MARK: - Persisted sessions JSON codec (StudyChatSessionStorage.kt)
// Mirrors the Android `study_suit_sessions_v1.json` format so sessions produced on
// either platform are interchangeable.

enum SessionStorageError: Error {
    case invalidPayload
}

func parsePersistedSessionsJson(_ raw: String) -> Result<PersistedSessions, Error> {
    do {
        guard let root = JSON.parse(raw), let rootDict = root as? [String: Any] else {
            throw SessionStorageError.invalidPayload
        }
        let activeSessionId = optString(root, key: "activeSessionId").trimmingCharacters(in: .whitespacesAndNewlines)
        let settings: RuntimeSettings
        if let settingsJson = optDictionary(root, key: "settings") {
            settings = toRuntimeSettings(settingsJson)
        } else {
            settings = RuntimeSettings.defaults()
        }
        let sessions: [StoredSession] = (optArray(root, key: "sessions") ?? []).compactMap { toStoredSession($0) }
        return .success(PersistedSessions(activeSessionId: activeSessionId, settings: settings, sessions: sessions))
    } catch {
        return .failure(error)
    }
}

// MARK: - RuntimeSettings codec

func runtimeSettingsToJson(_ settings: RuntimeSettings) -> [String: Any] {
    return [
        "arkApiKey": settings.arkApiKey,
        "arkModel": settings.arkModel,
        "arkBaseUrl": settings.arkBaseUrl,
        "arkEndpoint": settings.arkEndpoint,
        "arkSystemPrompt": settings.arkSystemPrompt,
        "imagePrompt": settings.imagePrompt,
        "openSpeechApiKey": settings.openSpeechApiKey,
        "openSpeechResourceId": settings.openSpeechResourceId,
        "openSpeechSubmitUrl": settings.openSpeechSubmitUrl,
        "openSpeechQueryUrl": settings.openSpeechQueryUrl,
        "openSpeechUid": settings.openSpeechUid,
        "flowStudyServerUrl": settings.flowStudyServerUrl,
        "flowStudyDeviceId": settings.flowStudyDeviceId,
        "flowStudyDeviceToken": settings.flowStudyDeviceToken,
        "customModelBaseUrl": settings.customModelBaseUrl,
        "customModelApiKey": settings.customModelApiKey,
        "customModelName": settings.customModelName,
        "customModelPresets": settings.customModelPresets.map { modelPresetToJson($0) }
    ]
}

func toRuntimeSettings(_ json: Any?) -> RuntimeSettings {
    let defaults = RuntimeSettings.defaults()
    let rawArkModel = optString(json, key: "arkModel").trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedArkModel: String
    if rawArkModel.isEmpty {
        normalizedArkModel = defaults.arkModel
    } else if rawArkModel == LEGACY_ARK_MODEL {
        normalizedArkModel = defaults.arkModel
    } else {
        normalizedArkModel = rawArkModel
    }
    let presets = (optArray(json, key: "customModelPresets") ?? []).enumerated().compactMap { (index, item) -> ModelPreset? in
        return toModelPreset(item, fallbackId: "preset-\(index)")
    }
    return RuntimeSettings(
        arkApiKey: optString(json, key: "arkApiKey").isEmpty ? defaults.arkApiKey : optString(json, key: "arkApiKey"),
        arkModel: normalizedArkModel,
        arkBaseUrl: optString(json, key: "arkBaseUrl").isEmpty ? defaults.arkBaseUrl : optString(json, key: "arkBaseUrl"),
        arkEndpoint: optString(json, key: "arkEndpoint").isEmpty ? defaults.arkEndpoint : optString(json, key: "arkEndpoint"),
        arkSystemPrompt: optString(json, key: "arkSystemPrompt").isEmpty ? defaults.arkSystemPrompt : optString(json, key: "arkSystemPrompt"),
        imagePrompt: optString(json, key: "imagePrompt").isEmpty ? defaults.imagePrompt : optString(json, key: "imagePrompt"),
        openSpeechApiKey: optString(json, key: "openSpeechApiKey").isEmpty ? defaults.openSpeechApiKey : optString(json, key: "openSpeechApiKey"),
        openSpeechResourceId: optString(json, key: "openSpeechResourceId").isEmpty ? defaults.openSpeechResourceId : optString(json, key: "openSpeechResourceId"),
        openSpeechSubmitUrl: optString(json, key: "openSpeechSubmitUrl").isEmpty ? defaults.openSpeechSubmitUrl : optString(json, key: "openSpeechSubmitUrl"),
        openSpeechQueryUrl: optString(json, key: "openSpeechQueryUrl").isEmpty ? defaults.openSpeechQueryUrl : optString(json, key: "openSpeechQueryUrl"),
        openSpeechUid: optString(json, key: "openSpeechUid").isEmpty ? defaults.openSpeechUid : optString(json, key: "openSpeechUid"),
        flowStudyServerUrl: optString(json, key: "flowStudyServerUrl").isEmpty ? defaults.flowStudyServerUrl : optString(json, key: "flowStudyServerUrl"),
        flowStudyDeviceId: optString(json, key: "flowStudyDeviceId"),
        flowStudyDeviceToken: optString(json, key: "flowStudyDeviceToken"),
        customModelBaseUrl: optString(json, key: "customModelBaseUrl"),
        customModelApiKey: optString(json, key: "customModelApiKey"),
        customModelName: optString(json, key: "customModelName"),
        customModelPresets: presets
    )
}

func modelPresetToJson(_ preset: ModelPreset) -> [String: Any] {
    return [
        "id": preset.id,
        "name": preset.name,
        "baseUrl": preset.baseUrl,
        "apiKey": preset.apiKey,
        "modelName": preset.modelName
    ]
}

func toModelPreset(_ json: Any?, fallbackId: String) -> ModelPreset? {
    let id = optString(json, key: "id").trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedId = id.isEmpty ? fallbackId : id
    let name = optString(json, key: "name").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    return ModelPreset(
        id: resolvedId,
        name: name,
        baseUrl: optString(json, key: "baseUrl").trimmingCharacters(in: .whitespacesAndNewlines),
        apiKey: optString(json, key: "apiKey").trimmingCharacters(in: .whitespacesAndNewlines),
        modelName: optString(json, key: "modelName").trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

// MARK: - StoredSession codec

func storedSessionToJson(_ session: StoredSession) -> [String: Any] {
    var json: [String: Any] = [
        "id": session.id,
        "title": session.title,
        "createdAt": session.createdAt,
        "updatedAt": session.updatedAt,
        "input": session.input,
        "coachInput": session.coachInput,
        "activePage": session.activePage.rawValue,
        "coachMessages": session.coachMessages.map { coachChatMessageToJson($0) },
        "dailyTraining": dailyTrainingStateToJson(session.dailyTraining),
        "savedQuestions": session.savedQuestions.map { savedQuestionToJson($0) },
        "profile": profileStateToJson(session.profile),
        "messages": session.messages.map { chatMessageToJson($0) },
        "knowledgePoints": knowledgePointsToJson(session.knowledgePoints),
        "ankiCards": session.ankiCards.map { ankiCardToJson($0) },
        "histories": historiesToJson(session.histories)
    ]
    if let value = session.quickFollowupSpanId { json["quickFollowupSpanId"] = value }
    if let value = session.quickFollowupDetailId { json["quickFollowupDetailId"] = value }
    if let digest = session.coachDigest { json["coachDigest"] = coachDailyDigestToJson(digest) }
    return json
}

func toStoredSession(_ json: Any?) -> StoredSession? {
    let id = optString(json, key: "id").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return nil }

    let title = optString(json, key: "title").ifBlank { "主界面" }
    let createdAt = optLong(json, key: "createdAt", default: currentTimeMillis())
    let updatedAt = optLong(json, key: "updatedAt", default: createdAt)
    let input = optString(json, key: "input")
    let coachInput = optString(json, key: "coachInput")

    let profile = optObjectAny(json, key: "profile").map { toProfileState($0) } ?? ProfileState(level: "高二 · 进阶冲刺")
    let messages = (optArray(json, key: "messages") ?? []).compactMap { toChatMessage($0) }
    let histories = (optDictionary(json, key: "histories") ?? [:]).reduce(into: [String: [SpanDetail]]()) { result, entry in
        guard let details = entry.value as? [Any] else { return }
        result[entry.key] = details.compactMap { toSpanDetail($0) }
    }
    let activePage = WorkspacePage.from(optString(json, key: "activePage"))
    let quickFollowupSpanId = optString(json, key: "quickFollowupSpanId").trimOrNull()
    let quickFollowupDetailId = optString(json, key: "quickFollowupDetailId").trimOrNull()
    let coachMessages = (optArray(json, key: "coachMessages") ?? []).compactMap { toCoachChatMessage($0) }
    let coachDigest = optObjectAny(json, key: "coachDigest").map { toCoachDailyDigest($0) }
    let dailyTraining = optObjectAny(json, key: "dailyTraining").map { toDailyTrainingState($0) } ?? DailyTrainingState()
    let savedQuestions = (optArray(json, key: "savedQuestions") ?? []).compactMap { toSavedQuestion($0) }
    let knowledgePoints = (optDictionary(json, key: "knowledgePoints") ?? [:]).reduce(into: [String: Int]()) { result, entry in
        result[entry.key] = intValue(entry.value)
    }
    let ankiCards = (optArray(json, key: "ankiCards") ?? []).compactMap { toAnkiCard($0) }

    return StoredSession(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        messages: messages,
        histories: histories,
        profile: profile,
        input: input,
        coachInput: coachInput,
        activePage: activePage,
        quickFollowupSpanId: quickFollowupSpanId,
        quickFollowupDetailId: quickFollowupDetailId,
        coachMessages: coachMessages,
        coachDigest: coachDigest,
        dailyTraining: dailyTraining,
        savedQuestions: savedQuestions,
        knowledgePoints: knowledgePoints,
        ankiCards: ankiCards
    )
}

// MARK: - ProfileState codec

func profileStateToJson(_ profile: ProfileState) -> [String: Any] {
    return [
        "level": profile.level,
        "followups": profile.followups,
        "voiceFollowups": profile.voiceFollowups,
        "topicHits": profile.topicHits
    ]
}

func toProfileState(_ json: Any?) -> ProfileState {
    let topicHits = (optDictionary(json, key: "topicHits") ?? [:]).reduce(into: [String: Int]()) { result, entry in
        result[entry.key] = intValue(entry.value)
    }
    return ProfileState(
        level: optString(json, key: "level").ifBlank { "高二 · 进阶冲刺" },
        topicHits: topicHits,
        followups: optInt(json, key: "followups", default: 0),
        voiceFollowups: optInt(json, key: "voiceFollowups", default: 0)
    )
}

// MARK: - ChatMessage codec

func chatMessageToJson(_ message: ChatMessage) -> [String: Any] {
    switch message {
    case .user(let id, let time, let text, let imagePreviewBytes, let imagePreviewList):
        let previewList: [Data]
        if !imagePreviewList.isEmpty {
            previewList = imagePreviewList
        } else if let bytes = imagePreviewBytes {
            previewList = [bytes]
        } else {
            previewList = []
        }
        let images = previewList.map { $0.base64EncodedString() }
        var json: [String: Any] = [
            "type": "user",
            "id": id,
            "time": time,
            "text": text,
            "images": images
        ]
        if let first = previewList.first { json["image"] = first.base64EncodedString() }
        return json
    case .assistant(let id, let time, let spans, let mainSpan, let reasoningSummary):
        var json: [String: Any] = [
            "type": "assistant",
            "id": id,
            "time": time,
            "spans": spans.map { spanDataToJson($0) }
        ]
        if let mainSpan = mainSpan {
            json["mainSpan"] = spanDataToJson(mainSpan)
        }
        if let reasoningSummary = reasoningSummary {
            json["reasoningSummary"] = reasoningSummary
        }
        return json
    }
}

func toChatMessage(_ json: Any?) -> ChatMessage? {
    let type = optString(json, key: "type")
    switch type {
    case "user":
        let imageList = (optArray(json, key: "images") ?? []).compactMap { encoded -> Data? in
            let s = optString(encoded)
            guard !s.isEmpty, s != "null" else { return nil }
            return Data(base64Encoded: s)
        }.filter { !$0.isEmpty }

        let encodedImage = optString(json, key: "image")
        let legacyImage: Data?
        if encodedImage.isEmpty || encodedImage == "null" {
            legacyImage = nil
        } else {
            legacyImage = Data(base64Encoded: encodedImage)
        }

        let previewList: [Data]
        if !imageList.isEmpty {
            previewList = imageList
        } else if let bytes = legacyImage, !bytes.isEmpty {
            previewList = [bytes]
        } else {
            previewList = []
        }

        return .user(
            id: optString(json, key: "id"),
            time: optString(json, key: "time"),
            text: optString(json, key: "text"),
            imagePreviewBytes: previewList.first,
            imagePreviewList: previewList
        )
    case "assistant":
        let spans = (optArray(json, key: "spans") ?? []).compactMap { toSpanData($0) }
        let mainSpan = optObjectAny(json, key: "mainSpan").map { toSpanData($0) } ?? buildLegacyMainSpan(messageId: optString(json, key: "id"), spans: spans)
        let reasoningRaw = optString(json, key: "reasoningSummary")
        let reasoningSummary = (reasoningRaw.isEmpty || reasoningRaw == "null") ? nil : reasoningRaw
        return .assistant(
            id: optString(json, key: "id"),
            time: optString(json, key: "time"),
            spans: spans,
            mainSpan: mainSpan,
            reasoningSummary: reasoningSummary
        )
    default:
        return nil
    }
}

func spanDataToJson(_ span: SpanData) -> [String: Any] {
    return [
        "id": span.id,
        "content": span.content,
        "sourceQuestion": span.sourceQuestion
    ]
}

func toSpanData(_ json: Any?) -> SpanData? {
    let id = optString(json, key: "id")
    return SpanData(
        id: id,
        content: optString(json, key: "content"),
        sourceQuestion: optString(json, key: "sourceQuestion")
    )
}

func buildLegacyMainSpan(messageId: String, spans: [SpanData]) -> SpanData? {
    if spans.isEmpty { return nil }
    let fullAnswer = spans
        .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if fullAnswer.isEmpty { return nil }
    let sourceQuestion = spans.first(where: { !$0.sourceQuestion.isEmpty })?.sourceQuestion ?? ""
    return SpanData(
        id: "assistant-main-\(messageId.isEmpty ? "legacy" : messageId)",
        content: fullAnswer,
        sourceQuestion: sourceQuestion
    )
}

// MARK: - SpanDetail codec

func spanDetailToJson(_ detail: SpanDetail) -> [String: Any] {
    var json: [String: Any] = [
        "id": detail.id,
        "mode": detail.mode,
        "time": detail.time,
        "answer": detail.answer
    ]
    if let question = detail.question { json["question"] = question }
    if let parentDetailId = detail.parentDetailId { json["parentDetailId"] = parentDetailId }
    if let summary = detail.summary { json["summary"] = summary }
    return json
}

func toSpanDetail(_ json: Any?) -> SpanDetail? {
    let id = optString(json, key: "id")
    guard !id.isEmpty else { return nil }
    let questionRaw = optString(json, key: "question")
    let question = (questionRaw.isEmpty || questionRaw == "null") ? nil : questionRaw
    let parentRaw = optString(json, key: "parentDetailId")
    let parentDetailId = (parentRaw.isEmpty || parentRaw == "null") ? nil : parentRaw
    let summaryRaw = optString(json, key: "summary")
    let summary = (summaryRaw.isEmpty || summaryRaw == "null") ? nil : summaryRaw
    return SpanDetail(
        id: id,
        mode: optString(json, key: "mode"),
        time: optString(json, key: "time"),
        question: question,
        answer: optString(json, key: "answer"),
        parentDetailId: parentDetailId,
        summary: summary
    )
}

func historiesToJson(_ histories: [String: [SpanDetail]]) -> [String: Any] {
    var json: [String: Any] = [:]
    for (spanId, details) in histories {
        json[spanId] = details.map { spanDetailToJson($0) }
    }
    return json
}

// MARK: - SavedQuestion codec

func savedQuestionToJson(_ saved: SavedQuestion) -> [String: Any] {
    let previewList: [Data]
    if !saved.imagePreviewList.isEmpty {
        previewList = saved.imagePreviewList
    } else if let bytes = saved.imagePreviewBytes {
        previewList = [bytes]
    } else {
        previewList = []
    }
    var json: [String: Any] = [
        "id": saved.id,
        "sourceMessageId": saved.sourceMessageId,
        "question": saved.question,
        "answer": saved.answer,
        "sourceTime": saved.sourceTime,
        "savedAt": saved.savedAt,
        "followupCount": saved.followupCount,
        "knowledgeTags": saved.knowledgeTags,
        "subject": saved.subject,
        "questionType": saved.questionType,
        "analysisSummary": saved.analysisSummary,
        "images": previewList.map { $0.base64EncodedString() }
    ]
    if let first = previewList.first { json["image"] = first.base64EncodedString() }
    return json
}

func toSavedQuestion(_ json: Any?) -> SavedQuestion? {
    let id = optString(json, key: "id").trimmingCharacters(in: .whitespacesAndNewlines)
    let question = optString(json, key: "question").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, !question.isEmpty else { return nil }

    let imageList = (optArray(json, key: "images") ?? []).compactMap { encoded -> Data? in
        let s = optString(encoded)
        guard !s.isEmpty, s != "null" else { return nil }
        return Data(base64Encoded: s)
    }.filter { !$0.isEmpty }
    let encodedImage = optString(json, key: "image")
    let legacyImage: Data? = (encodedImage.isEmpty || encodedImage == "null") ? nil : Data(base64Encoded: encodedImage)
    let previewList: [Data]
    if !imageList.isEmpty {
        previewList = imageList
    } else if let bytes = legacyImage, !bytes.isEmpty {
        previewList = [bytes]
    } else {
        previewList = []
    }

    let knowledgeTags = (optArray(json, key: "knowledgeTags") ?? []).map { optString($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

    return SavedQuestion(
        id: id,
        sourceMessageId: optString(json, key: "sourceMessageId").trimmingCharacters(in: .whitespacesAndNewlines),
        question: question,
        answer: optString(json, key: "answer"),
        sourceTime: optString(json, key: "sourceTime"),
        savedAt: optLong(json, key: "savedAt", default: currentTimeMillis()),
        followupCount: max(0, optInt(json, key: "followupCount", default: 0)),
        knowledgeTags: knowledgeTags,
        subject: optString(json, key: "subject").trimmingCharacters(in: .whitespacesAndNewlines),
        questionType: optString(json, key: "questionType").trimmingCharacters(in: .whitespacesAndNewlines),
        analysisSummary: optString(json, key: "analysisSummary").trimmingCharacters(in: .whitespacesAndNewlines),
        imagePreviewBytes: previewList.first,
        imagePreviewList: previewList
    )
}

// MARK: - AnkiCard codec

func ankiCardToJson(_ card: AnkiCard) -> [String: Any] {
    var json: [String: Any] = [
        "id": card.id,
        "front": card.front,
        "back": card.back,
        "tags": card.tags,
        "source": card.source,
        "createdAt": card.createdAt,
        "nextReviewAt": card.nextReviewAt,
        "reviewCount": card.reviewCount,
        "mastery": card.mastery.rawValue,
        "deck": card.deckName
    ]
    if let lastReviewedAt = card.lastReviewedAt { json["lastReviewedAt"] = lastReviewedAt }
    return json
}

func toAnkiCard(_ json: Any?) -> AnkiCard? {
    let id = optString(json, key: "id").ifBlank { "card-\(currentTimeMillis())-\(UUID().uuidString.prefix(6))" }
    let tags = (optArray(json, key: "tags") ?? []).map { optString($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    let createdAt = optLong(json, key: "createdAt", default: currentTimeMillis())
    let nextReviewAt = optLong(json, key: "nextReviewAt", default: optLong(json, key: "createdAt", default: createdAt))
    let reviewCount = max(0, optInt(json, key: "reviewCount", default: 0))
    let lastReviewedAtRaw = optLong(json, key: "lastReviewedAt", default: -1)
    let lastReviewedAt = lastReviewedAtRaw > 0 ? lastReviewedAtRaw : nil
    let mastery = CardMasteryLevel.from(optString(json, key: "mastery"))
    let deck = optString(json, key: "deck").trimmingCharacters(in: .whitespacesAndNewlines).trimOrNull() ?? DEFAULT_ANKI_DECK_NAME
    return AnkiCard(
        id: id,
        front: optString(json, key: "front"),
        back: optString(json, key: "back"),
        tags: tags,
        source: optString(json, key: "source"),
        createdAt: createdAt,
        nextReviewAt: nextReviewAt,
        reviewCount: reviewCount,
        lastReviewedAt: lastReviewedAt,
        mastery: mastery,
        deckName: deck
    )
}

// MARK: - Coach codecs

func coachChatMessageToJson(_ message: CoachChatMessage) -> [String: Any] {
    return [
        "id": message.id,
        "role": message.role.rawValue,
        "time": message.time,
        "text": message.text
    ]
}

func toCoachChatMessage(_ json: Any?) -> CoachChatMessage? {
    let id = optString(json, key: "id").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return nil }
    let text = optString(json, key: "text").trimmingCharacters(in: .whitespacesAndNewlines)
    return CoachChatMessage(
        id: id,
        role: CoachMessageRole.from(optString(json, key: "role")),
        time: optString(json, key: "time"),
        text: text
    )
}

func coachDailyDigestToJson(_ digest: CoachDailyDigest) -> [String: Any] {
    return [
        "dateKey": digest.dateKey,
        "generatedAt": digest.generatedAt,
        "headline": digest.headline,
        "summary": digest.summary,
        "focusAreas": digest.focusAreas.map { coachFocusAreaToJson($0) },
        "recommendedQuestions": digest.recommendedQuestions.map { coachRecommendedQuestionToJson($0) }
    ]
}

func toCoachDailyDigest(_ json: Any?) -> CoachDailyDigest {
    return CoachDailyDigest(
        dateKey: optString(json, key: "dateKey"),
        generatedAt: optLong(json, key: "generatedAt", default: currentTimeMillis()),
        headline: optString(json, key: "headline"),
        summary: optString(json, key: "summary"),
        focusAreas: (optArray(json, key: "focusAreas") ?? []).compactMap { toCoachFocusArea($0) },
        recommendedQuestions: (optArray(json, key: "recommendedQuestions") ?? []).compactMap { toCoachRecommendedQuestion($0) }
    )
}

func coachFocusAreaToJson(_ area: CoachFocusArea) -> [String: Any] {
    return [
        "point": area.point,
        "level": area.level.rawValue,
        "diagnosis": area.diagnosis,
        "action": area.action,
        "evidence": area.evidence
    ]
}

func toCoachFocusArea(_ json: Any?) -> CoachFocusArea? {
    let point = optString(json, key: "point").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !point.isEmpty else { return nil }
    return CoachFocusArea(
        point: point,
        level: KnowledgeGapLevel.from(optString(json, key: "level")),
        diagnosis: optString(json, key: "diagnosis"),
        action: optString(json, key: "action"),
        evidence: optString(json, key: "evidence")
    )
}

func coachRecommendedQuestionToJson(_ question: CoachRecommendedQuestion) -> [String: Any] {
    var json: [String: Any] = [
        "id": question.id,
        "title": question.title,
        "reason": question.reason,
        "prompt": question.prompt,
        "basis": question.basis
    ]
    if let anchor = question.anchorSavedQuestionId { json["anchorSavedQuestionId"] = anchor }
    return json
}

func toCoachRecommendedQuestion(_ json: Any?) -> CoachRecommendedQuestion? {
    let prompt = optString(json, key: "prompt").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else { return nil }
    let index = 0
    let id = optString(json, key: "id").trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { "coach-rec-\(index)" }
    let anchor = optString(json, key: "anchorSavedQuestionId").trimmingCharacters(in: .whitespacesAndNewlines).trimOrNull()
    return CoachRecommendedQuestion(
        id: id,
        title: optString(json, key: "title"),
        reason: optString(json, key: "reason"),
        prompt: prompt,
        basis: optString(json, key: "basis"),
        anchorSavedQuestionId: anchor
    )
}

func dailyTrainingStateToJson(_ state: DailyTrainingState) -> [String: Any] {
    return [
        "dateKey": state.dateKey,
        "currentIndex": state.currentIndex,
        "phase": state.phase.rawValue,
        "currentQuestionText": state.currentQuestionText,
        "rounds": state.rounds.map { coachRecommendedQuestionToJson($0) }
    ]
}

func toDailyTrainingState(_ json: Any?) -> DailyTrainingState {
    return DailyTrainingState(
        dateKey: optString(json, key: "dateKey"),
        rounds: (optArray(json, key: "rounds") ?? []).compactMap { toCoachRecommendedQuestion($0) },
        currentIndex: max(0, optInt(json, key: "currentIndex", default: 0)),
        phase: DailyTrainingPhase.from(optString(json, key: "phase")),
        currentQuestionText: optString(json, key: "currentQuestionText")
    )
}

// MARK: - Root payload

func buildRootJson(_ payload: PersistedSessions) -> [String: Any] {
    return [
        "version": 1,
        "activeSessionId": payload.activeSessionId,
        "settings": runtimeSettingsToJson(payload.settings),
        "sessions": payload.sessions.map { storedSessionToJson($0) }
    ]
}

func knowledgePointsToJson(_ knowledgePoints: [String: Int]) -> [String: Any] {
    return Dictionary(knowledgePoints)
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        return isEmpty ? fallback : self
    }
}
