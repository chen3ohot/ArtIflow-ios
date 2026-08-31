import Foundation

// MARK: - Knowledge point canonicalization (StudyChatViewModelSupport.kt)

func detectRuleBasedKnowledgePoints(_ text: String) -> [String] {
    let normalized = text.lowercased()
    return modelKnowledgeRules
        .filter { rule in rule.keywords.contains { normalized.contains($0.lowercased()) } }
        .map { $0.point }
        .deduplicated()
}

func canonicalizeHighSchoolKnowledgePoint(_ text: String) -> [String] {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty { return [] }

    if canonicalHighSchoolKnowledgePoints.contains(normalized) {
        return [normalized]
    }

    let tagged = QuestionTagger.autoTag(normalized)
    let taggedPoints = tagged.knowledgePoints
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .deduplicated()
    if supportedKnowledgeSubjects.contains(tagged.subject) && !taggedPoints.isEmpty {
        return taggedPoints
    }
    return detectRuleBasedKnowledgePoints(normalized)
}

func inferKnowledgePoints(_ text: String) -> [String] {
    return canonicalizeHighSchoolKnowledgePoint(text)
}

func filterToHighSchoolKnowledgeTags(_ tags: [String], maxSize: Int = 6) -> [String] {
    var result: [String] = []
    for tag in tags {
        for point in canonicalizeHighSchoolKnowledgePoint(tag) {
            if !result.contains(point) { result.append(point) }
            if result.count >= maxSize { return result }
        }
    }
    return result
}

func isValidHighSchoolDeckSuggestion(_ raw: String?) -> Bool {
    var normalized = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    for suffix in ["卡组", "专练", "训练"] {
        if normalized.hasSuffix(suffix) {
            normalized = String(normalized.dropLast(suffix.count))
            break
        }
    }
    normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty { return false }
    if supportedKnowledgeSubjects.contains(QuestionTagger.detectSubject(normalized)) {
        return true
    }
    return !canonicalizeHighSchoolKnowledgePoint(normalized).isEmpty
}

func sanitizeKnowledgePointsMap(_ knowledgePoints: [String: Int], maxSize: Int = 32) -> [String: Int] {
    if knowledgePoints.isEmpty { return [:] }
    var sanitized: [String: Int] = [:]
    let orderedKeys = knowledgePoints.keys.sorted() // stable-ish; Kotlin uses insertion order
    for rawPoint in orderedKeys {
        let count = max(0, knowledgePoints[rawPoint] ?? 0)
        if count <= 0 { continue }
        for point in filterToHighSchoolKnowledgeTags([rawPoint], maxSize: 6) {
            sanitized[point, default: 0] += count
        }
    }
    // preserve insertion order up to maxSize
    var result: [String: Int] = [:]
    for (key, value) in sanitized where result.count < maxSize {
        result[key] = value
    }
    return result
}

func sanitizeSavedQuestion(_ saved: SavedQuestion) -> SavedQuestion? {
    let question = saved.question.trimmingCharacters(in: .whitespacesAndNewlines)
    let answer = saved.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    if question.isEmpty || answer.isEmpty { return nil }

    let previewList: [Data]
    if !saved.imagePreviewList.isEmpty {
        previewList = saved.imagePreviewList.filter { !$0.isEmpty }.prefix(6).map { $0 }
    } else if let bytes = saved.imagePreviewBytes, !bytes.isEmpty {
        previewList = [bytes]
    } else {
        previewList = []
    }

    return SavedQuestion(
        id: saved.id,
        sourceMessageId: saved.sourceMessageId,
        question: question,
        answer: answer,
        sourceTime: saved.sourceTime,
        savedAt: saved.savedAt,
        followupCount: saved.followupCount,
        knowledgeTags: filterToHighSchoolKnowledgeTags(saved.knowledgeTags, maxSize: 6),
        subject: saved.subject.trimmingCharacters(in: .whitespacesAndNewlines),
        questionType: saved.questionType.trimmingCharacters(in: .whitespacesAndNewlines),
        analysisSummary: saved.analysisSummary.trimmingCharacters(in: .whitespacesAndNewlines),
        imagePreviewBytes: previewList.first,
        imagePreviewList: previewList
    )
}

func sanitizeAnkiCard(_ card: AnkiCard) -> AnkiCard {
    let tags = filterToHighSchoolKnowledgeTags(card.tags, maxSize: 10)
    return AnkiCard(
        id: card.id,
        front: card.front,
        back: card.back,
        tags: tags,
        source: card.source,
        createdAt: card.createdAt,
        nextReviewAt: card.nextReviewAt,
        reviewCount: card.reviewCount,
        lastReviewedAt: card.lastReviewedAt,
        mastery: card.mastery,
        deckName: sanitizeDeckNameForStoredCard(card.deckName, tags: tags)
    )
}

func sanitizeDeckNameForStoredCard(_ deckName: String?, tags: [String]) -> String {
    let normalizedDeck = normalizeDeckName(deckName)
    if let normalized = normalizedDeck, !normalized.isEmpty {
        if normalized.caseInsensitiveCompare(DEFAULT_ANKI_DECK_NAME) == .orderedSame {
            return DEFAULT_ANKI_DECK_NAME
        }
        if isValidHighSchoolDeckSuggestion(normalized) {
            return normalized
        }
    }
    let firstTag = filterToHighSchoolKnowledgeTags(tags, maxSize: 1).first
    if let point = firstTag {
        return normalizeDeckName("\(point.trimmingCharacters(in: .whitespacesAndNewlines))卡组") ?? DEFAULT_ANKI_DECK_NAME
    }
    return DEFAULT_ANKI_DECK_NAME
}

func normalizeDeckName(_ raw: String?) -> String? {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .prefix(12)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Anki operations

func prependAnkiCard(_ current: [AnkiCard], card: AnkiCard) -> [AnkiCard] {
    let deduplicated = current.filter { existing in
        !(existing.front == card.front && existing.back == card.back)
    }
    return [card] + Array(deduplicated.prefix(199))
}

func sortAnkiCardsForReview(_ cards: [AnkiCard]) -> [AnkiCard] {
    return cards.sorted { lhs, rhs in
        if lhs.mastery.reviewPriority != rhs.mastery.reviewPriority {
            return lhs.mastery.reviewPriority < rhs.mastery.reviewPriority
        }
        return lhs.createdAt > rhs.createdAt
    }
}

func isCardDueForReview(_ card: AnkiCard, now: Int64 = currentTimeMillis()) -> Bool {
    return card.nextReviewAt <= now
}

func dueReviewCards(_ cards: [AnkiCard], now: Int64 = currentTimeMillis()) -> [AnkiCard] {
    return cards
        .filter { isCardDueForReview($0, now: now) }
        .sorted { lhs, rhs in
            if lhs.nextReviewAt != rhs.nextReviewAt { return lhs.nextReviewAt < rhs.nextReviewAt }
            if lhs.mastery.reviewPriority != rhs.mastery.reviewPriority {
                return lhs.mastery.reviewPriority < rhs.mastery.reviewPriority
            }
            return lhs.createdAt > rhs.createdAt
        }
}

func countDueReviewCards(_ cards: [AnkiCard], now: Int64 = currentTimeMillis()) -> Int {
    return dueReviewCards(cards, now: now).count
}

func applySrsReview(_ card: AnkiCard, mastery: CardMasteryLevel, reviewedAt: Int64 = currentTimeMillis()) -> AnkiCard {
    let intervalDays: Int64
    switch mastery {
    case .unrated: intervalDays = 0
    case .needsWork: intervalDays = 1
    case .familiar: intervalDays = 3
    case .proficient: intervalDays = 7
    }
    let nextReviewAt = intervalDays <= 0 ? reviewedAt : reviewedAt + intervalDays * MILLIS_PER_DAY
    return AnkiCard(
        id: card.id,
        front: card.front,
        back: card.back,
        tags: card.tags,
        source: card.source,
        createdAt: card.createdAt,
        nextReviewAt: nextReviewAt,
        reviewCount: card.reviewCount + 1,
        lastReviewedAt: reviewedAt,
        mastery: mastery,
        deckName: card.deckName
    )
}

func mergeGlobalAnkiCards(_ sessions: [StoredSession]) -> [AnkiCard] {
    var mergedByContent: [String: AnkiCard] = [:]
    var order: [String] = []
    for session in sessions {
        for card in session.ankiCards {
            let key = "\(card.front.trimmingCharacters(in: .whitespacesAndNewlines))\u{0001}\(card.back.trimmingCharacters(in: .whitespacesAndNewlines))"
            if let existing = mergedByContent[key] {
                mergedByContent[key] = pickPreferredGlobalCard(existing: existing, candidate: card)
            } else {
                mergedByContent[key] = card
                order.append(key)
            }
        }
    }
    let ordered = order.compactMap { mergedByContent[$0] }
    return sortAnkiCardsForReview(ordered)
}

private func pickPreferredGlobalCard(existing: AnkiCard, candidate: AnkiCard) -> AnkiCard {
    let existingReviewMoment = existing.lastReviewedAt ?? Int64.min
    let candidateReviewMoment = candidate.lastReviewedAt ?? Int64.min
    if candidateReviewMoment > existingReviewMoment { return candidate }
    if candidateReviewMoment < existingReviewMoment { return existing }
    if candidate.reviewCount > existing.reviewCount { return candidate }
    if candidate.reviewCount < existing.reviewCount { return existing }
    if candidate.createdAt > existing.createdAt { return candidate }
    return existing
}

func detectExistingDeckCategories(_ cards: [AnkiCard]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for card in cards {
        let deck = card.deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !deck.isEmpty && !seen.contains(deck) {
            seen.insert(deck)
            result.append(deck)
        }
    }
    return result
}

func resolveDeckNameForAutoCard(suggestedDeck: String?, tags: [String], existingCards: [AnkiCard]) -> String {
    let existingDecks = detectExistingDeckCategories(existingCards)
    let normalizedSuggestion = normalizeDeckName(suggestedDeck)

    if let normalized = normalizedSuggestion {
        if let matched = existingDecks.first(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return matched
        }
        if isValidHighSchoolDeckSuggestion(normalized) {
            return normalized
        }
    }

    let normalizedTags = Set(
        filterToHighSchoolKnowledgeTags(tags, maxSize: 10)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    )

    if !normalizedTags.isEmpty {
        let grouped = Dictionary(grouping: existingCards, by: { $0.deckName })
        var bestDeck: (deck: String, score: Int)? = nil
        for (deck, cardsInDeck) in grouped {
            let deckTags = Set(
                cardsInDeck.flatMap { card -> [String] in
                    let normalized = filterToHighSchoolKnowledgeTags(card.tags, maxSize: 10)
                    return normalized.isEmpty ? card.tags : normalized
                }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
            let score = normalizedTags.filter { deckTags.contains($0) }.count
            if score > 0 {
                if bestDeck == nil || score > bestDeck!.score {
                    bestDeck = (deck, score)
                }
            }
        }
        if let matched = bestDeck, !matched.deck.isEmpty {
            return matched.deck
        }
    }

    let firstTag = filterToHighSchoolKnowledgeTags(tags, maxSize: 1).first
    if let point = firstTag, !point.isEmpty {
        return normalizeDeckName("\(point.trimmingCharacters(in: .whitespacesAndNewlines))卡组") ?? DEFAULT_ANKI_DECK_NAME
    }

    return existingDecks.first { $0.caseInsensitiveCompare(DEFAULT_ANKI_DECK_NAME) == .orderedSame } ?? DEFAULT_ANKI_DECK_NAME
}

func buildAnkiDeckSummaries(_ cards: [AnkiCard]) -> [AnkiDeckSummary] {
    let grouped = Dictionary(grouping: cards, by: { normalizeDeckName($0.deckName) ?? DEFAULT_ANKI_DECK_NAME })
    var summaries = grouped.map { (deck, cardsInDeck) -> AnkiDeckSummary in
        var tagHits: [String: Int] = [:]
        var tagOrder: [String] = []
        for card in cardsInDeck {
            for tag in card.tags {
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                if tagHits[normalized] == nil { tagOrder.append(normalized) }
                tagHits[normalized, default: 0] += 1
            }
        }
        let topTags = tagOrder.sorted { (tagHits[$0] ?? 0) > (tagHits[$1] ?? 0) }.prefix(3).map { $0 }
        return AnkiDeckSummary(
            name: deck,
            cardCount: cardsInDeck.count,
            topTags: Array(topTags),
            needsWorkCount: cardsInDeck.filter { $0.mastery == .needsWork }.count,
            proficientCount: cardsInDeck.filter { $0.mastery == .proficient }.count
        )
    }
    summaries.sort { lhs, rhs in
        if lhs.cardCount != rhs.cardCount { return lhs.cardCount > rhs.cardCount }
        return lhs.name < rhs.name
    }
    return summaries
}

func buildDeckPracticeSummary(deckName: String, cards: [AnkiCard], selections: [String: CardMasteryLevel]) -> DeckPracticeSummary {
    let reviewed = Array(selections.values)
    return DeckPracticeSummary(
        deckName: deckName,
        totalCards: cards.count,
        reviewedCards: reviewed.count,
        needsWorkCount: reviewed.filter { $0 == .needsWork }.count,
        familiarCount: reviewed.filter { $0 == .familiar }.count,
        proficientCount: reviewed.filter { $0 == .proficient }.count
    )
}

// MARK: - Helpers

extension Array where Element: Equatable {
    func deduplicated() -> [Element] {
        var result: [Element] = []
        for item in self where !result.contains(item) { result.append(item) }
        return result
    }
}

extension String {
    func trimOrNull() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
