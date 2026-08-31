import Foundation

// MARK: - Knowledge gap insights (StudyChatViewModelSupport.kt buildKnowledgeGapInsights)

private let directWeakKeywords = [
    "不会", "不太会", "没学会", "没懂", "不懂", "不明白", "看不懂", "不会做", "卡住", "忘了"
]
private let reasoningGapKeywords = [
    "为什么", "怎么想到", "怎么判断", "哪里来", "依据", "凭什么", "为什么这样", "怎么得出"
]
private let methodGapKeywords = [
    "怎么做", "怎么下手", "思路", "方法", "步骤", "套路", "切入点", "先做什么"
]
private let conceptGapKeywords = [
    "概念", "定义", "性质", "公式", "定理", "判定", "条件", "含义", "是什么"
]

private final class KnowledgeGapStats {
    let point: String
    var exposureCount = 0
    var directWeakCount = 0
    var reasoningCount = 0
    var methodCount = 0
    var conceptCount = 0
    var threadedDepth = 0
    var evidenceSamples: [String] = []

    init(point: String) { self.point = point }
}

func buildKnowledgeGapInsights(
    messages: [ChatMessage],
    histories: [String: [SpanDetail]],
    knowledgePoints: [String: Int]
) -> [KnowledgeGapInsight] {
    var statsByPoint: [String: KnowledgeGapStats] = [:]
    var pointOrder: [String] = []

    func record(_ text: String, fallbackPoints: [String] = [], depthBoost: Int = 0) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return }

        var points = canonicalizeHighSchoolKnowledgePoint(normalized)
        for fb in fallbackPoints {
            let trimmed = fb.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !points.contains(trimmed) { points.append(trimmed) }
        }
        points = points.deduplicated()
        if points.isEmpty { return }

        let lowered = normalized.lowercased()
        let directWeakHits = directWeakKeywords.filter { lowered.contains($0) }.count
        let reasoningHits = reasoningGapKeywords.filter { lowered.contains($0) }.count
        let methodHits = methodGapKeywords.filter { lowered.contains($0) }.count
        let conceptHits = conceptGapKeywords.filter { lowered.contains($0) }.count
        let snippet = String(normalizeInlineText(normalized).prefix(28))

        for point in points {
            if statsByPoint[point] == nil { pointOrder.append(point) }
            let stats = statsByPoint[point] ?? KnowledgeGapStats(point: point)
            statsByPoint[point] = stats
            stats.exposureCount += 1
            stats.directWeakCount += directWeakHits
            stats.reasoningCount += reasoningHits
            stats.methodCount += methodHits
            stats.conceptCount += conceptHits
            stats.threadedDepth += depthBoost
            if !snippet.isEmpty && !stats.evidenceSamples.contains(snippet) {
                stats.evidenceSamples.append(snippet)
            }
        }
    }

    for message in messages {
        if case .user(_, _, let text, _, _) = message {
            record(text)
        }
    }

    for (spanId, details) in histories {
        let span = findSpanById(messages, spanId: spanId)
        var threadContext = ""
        if let span = span {
            if let sq = span.sourceQuestion.trimOrNull() { threadContext += sq + "\n" }
            if let c = span.content.trimOrNull() { threadContext += c }
        }
        let threadContextPoints = canonicalizeHighSchoolKnowledgePoint(threadContext)
        let extraDepth = max(details.count - 1, 0)
        if extraDepth > 0 {
            if let rootQuestion = details.first?.question?.trimOrNull() {
                record(rootQuestion, fallbackPoints: threadContextPoints, depthBoost: extraDepth)
            }
        }
        for (index, detail) in details.enumerated() {
            let branchDepth = detail.parentDetailId != nil ? index + 1 : 0
            if let question = detail.question {
                record(question, fallbackPoints: threadContextPoints, depthBoost: branchDepth)
            }
        }
    }

    let insights = pointOrder.compactMap { point -> KnowledgeGapInsight? in
        guard let stats = statsByPoint[point] else { return nil }
        let heatBoost = min(knowledgePoints[stats.point] ?? 0, 3)
        let score = stats.directWeakCount * 4
            + stats.reasoningCount * 3
            + stats.methodCount * 2
            + stats.conceptCount * 2
            + stats.threadedDepth * 2
            + stats.exposureCount
            + heatBoost
        let level: KnowledgeGapLevel
        switch score {
        case 10...: level = .high
        case 6...9: level = .medium
        default: level = .low
        }
        let diagnosis: String
        if stats.directWeakCount > 0 && stats.directWeakCount >= max(stats.reasoningCount, max(stats.methodCount, stats.conceptCount)) {
            diagnosis = "你多次直接表示这块不会或没懂，基础还不稳"
        } else if stats.conceptCount >= max(stats.reasoningCount, stats.methodCount) && stats.conceptCount > 0 {
            diagnosis = "更像定义、性质或判定条件没有真正吃透"
        } else if stats.reasoningCount >= stats.methodCount && stats.reasoningCount > 0 {
            diagnosis = "更像为什么这么做的依据链断了"
        } else if stats.methodCount > 0 {
            diagnosis = "更像切入点和解题步骤不够稳定"
        } else if stats.threadedDepth >= 2 {
            diagnosis = "同类问题连续追问，说明这里仍然卡住"
        } else {
            diagnosis = "这一块反复出现，建议回补基础再做题"
        }
        var evidenceParts: [String] = []
        if stats.exposureCount > 0 { evidenceParts.append("相关提问\(stats.exposureCount)次") }
        if stats.directWeakCount > 0 { evidenceParts.append("直接说不会/没懂\(stats.directWeakCount)次") }
        if stats.threadedDepth > 0 { evidenceParts.append("连续深追\(stats.threadedDepth)层") }
        var evidence = evidenceParts.joined(separator: " · ")
        if evidence.isEmpty { evidence = "已多次围绕这一点追问" }
        if let sample = stats.evidenceSamples.first {
            evidence += " · 例：\(sample)"
        }
        let action: String
        if stats.conceptCount > 0 {
            action = "先补 \(stats.point) 的定义、判定条件和常见误区，再做 1 道基础题验证。"
        } else if stats.reasoningCount > 0 {
            action = "把 \(stats.point) 每一步为什么能这样做写成依据链，再回到原题复现。"
        } else if stats.methodCount > 0 {
            action = "把 \(stats.point) 的标准切入步骤压成 3 步模板，重新走一遍原题。"
        } else {
            action = "先做 1-2 道同类型基础题，把 \(stats.point) 练熟后再继续追问。"
        }
        return KnowledgeGapInsight(point: stats.point, level: level, score: score, evidence: evidence, diagnosis: diagnosis, action: action)
    }

    return insights
        .filter { $0.score >= 4 }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.point < rhs.point
        }
        .prefix(5)
        .map { $0 }
}

// MARK: - Session seeds (StudyChatViewModelSupport.kt deriveSessionSeeds)

func deriveSessionSeeds(_ active: StoredSession) -> SessionSeeds {
    let messageIds = active.messages.map { $0.id } + active.coachMessages.map { $0.id }
    let messageSeed = messageIds.compactMap { id in
        Int(id.replacingOccurrences(of: "msg-", with: ""))
    }.max() ?? 0

    let spanSeed = active.messages.flatMap { message -> [String] in
        guard case .assistant = message else { return [] }
        return message.interactiveSpans().map { $0.id }
    }.compactMap { id in Int(id.replacingOccurrences(of: "span-", with: "")) }.max() ?? 0

    let detailSeed = active.histories.values.flatMap { $0 }.compactMap { detail in
        Int(detail.id.replacingOccurrences(of: "detail-", with: ""))
    }.max() ?? 0

    let cardSeed = active.ankiCards.compactMap { card in
        Int(card.id.replacingOccurrences(of: "card-", with: ""))
    }.max() ?? 0

    return SessionSeeds(messageSeed: messageSeed, spanSeed: spanSeed, detailSeed: detailSeed, cardSeed: cardSeed)
}
