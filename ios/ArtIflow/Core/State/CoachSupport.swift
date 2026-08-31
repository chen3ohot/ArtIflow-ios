import Foundation

// MARK: - Coach support (StudyCoachSupport.kt)

private let coachPunctuationPattern = "[。！？!?,，；;：:]+$"
private let coachWhitespacePattern = "\\s+"

private func makeRegex(_ pattern: String) -> NSRegularExpression {
    // swiftlint:disable:next force_try
    return try! NSRegularExpression(pattern: pattern, options: [])
}

private func normalizeCoachText(_ text: String) -> String {
    var result = text.replacingOccurrences(of: coachWhitespacePattern, with: " ", options: .regularExpression)
    let regex = makeRegex(coachPunctuationPattern)
    result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizeCoachSentence(_ text: String) -> String {
    var normalized = normalizeCoachText(text)
    while let last = normalized.last, "。！？".contains(last) {
        normalized.removeLast()
    }
    return normalized
}

private func normalizeCoachSnippet(_ text: String, maxLen: Int) -> String {
    let normalized = normalizeCoachText(text)
    return normalized.count <= maxLen ? normalized : String(normalized.prefix(maxLen)) + "…"
}

struct CoachQuickAction {
    let label: String
    let prompt: String
}

struct CoachReplyQuickAction {
    let label: String
    let prompt: String
}

struct CoachConversationTurn {
    let id: String
    let messages: [CoachChatMessage]
}

func buildCoachDailyDigest(
    messages: [ChatMessage],
    histories: [String: [SpanDetail]],
    savedQuestions: [SavedQuestion],
    knowledgePoints: [String: Int],
    nowMillis: Int64 = currentTimeMillis()
) -> CoachDailyDigest {
    let insights = buildKnowledgeGapInsights(messages: messages, histories: histories, knowledgePoints: knowledgePoints)
    let focusAreas = Array(insights.prefix(3).map { insight in
        CoachFocusArea(
            point: insight.point,
            level: insight.level,
            diagnosis: normalizeCoachText(insight.diagnosis),
            action: normalizeCoachText(insight.action),
            evidence: normalizeCoachText(insight.evidence)
        )
    })

    let practiceCount = messages.filter { if case .user = $0 { return true }; return false }.count
    let headline: String
    if focusAreas.isEmpty && practiceCount == 0 && savedQuestions.isEmpty {
        headline = "今天先给我几道题，我再当你的教练"
    } else if focusAreas.isEmpty {
        headline = "今天整体还算稳，继续保持做题手感"
    } else if focusAreas.count == 1 {
        headline = "今天先盯住 \(focusAreas.first!.point)"
    } else {
        headline = "今天重点补 \(focusAreas.map { $0.point }.joined(separator: "、"))"
    }
    let summary = buildCoachDigestSummary(focusAreas: focusAreas, practiceCount: practiceCount, savedCount: savedQuestions.count)
    let recommendedQuestions = buildCoachRecommendedQuestions(focusAreas: focusAreas, savedQuestions: savedQuestions, nowMillis: nowMillis)

    return CoachDailyDigest(
        dateKey: currentCoachDateKey(nowMillis: nowMillis),
        generatedAt: nowMillis,
        headline: headline,
        summary: summary,
        focusAreas: focusAreas,
        recommendedQuestions: recommendedQuestions
    )
}

func buildCoachConversationMessages(
    digest: CoachDailyDigest?,
    coachMessages: [CoachChatMessage],
    profile: ProfileState,
    knowledgePoints: [String: Int],
    knowledgeGapInsights: [KnowledgeGapInsight],
    savedQuestions: [SavedQuestion]
) -> [ArkRequestMessage] {
    let contextMessage = ArkRequestMessage(
        role: "user",
        text: buildCoachContextText(
            digest: digest,
            profile: profile,
            knowledgePoints: knowledgePoints,
            knowledgeGapInsights: knowledgeGapInsights,
            savedQuestions: savedQuestions
        )
    )
    let historyMessages = Array(coachMessages.suffix(10).compactMap { message -> ArkRequestMessage? in
        let normalized = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let role = message.role == .user ? "user" : "assistant"
        return ArkRequestMessage(role: role, text: normalized)
    })
    return [contextMessage] + historyMessages
}

func upsertCoachMessage(_ messages: [CoachChatMessage], target: CoachChatMessage) -> [CoachChatMessage] {
    if messages.contains(where: { $0.id == target.id }) {
        return messages.map { $0.id == target.id ? target : $0 }
    }
    return messages + [target]
}

func buildCoachConversationTurns(_ messages: [CoachChatMessage]) -> [CoachConversationTurn] {
    if messages.isEmpty { return [] }
    var turns: [CoachConversationTurn] = []
    var pending: [CoachChatMessage] = []

    func flushPending() {
        if pending.isEmpty { return }
        turns.append(CoachConversationTurn(id: pending.first!.id, messages: pending))
        pending.removeAll()
    }

    for message in messages {
        switch message.role {
        case .user:
            flushPending()
            pending.append(message)
        case .assistant:
            pending.append(message)
            flushPending()
        }
    }
    flushPending()
    return turns
}

func buildCoachQuickActions(_ digest: CoachDailyDigest?) -> [CoachQuickAction] {
    var actions: [CoachQuickAction] = [
        CoachQuickAction(
            label: "先说核心问题",
            prompt: "先直接告诉我：今天我最核心的问题是什么？只说最该先补的一点，再给我一个立刻能做的动作。"
        )
    ]
    if let area = digest?.focusAreas.first {
        actions.append(CoachQuickAction(
            label: "为什么卡\(area.point)",
            prompt: "为什么我在\(area.point)上总会卡住？请结合今天的表现，指出我最容易漏掉的判断点，再提醒我做这类题第一眼先看什么。"
        ))
    }
    if let question = digest?.recommendedQuestions.first {
        let title = question.title.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { "这道推荐题" }
        actions.append(CoachQuickAction(
            label: "练前先提醒我",
            prompt: "如果我现在开始练「\(title)」这类题，第一眼最该先判断什么？请给我一个很短的检查顺序。"
        ))
    }

    let cleaned = actions.compactMap { action -> CoachQuickAction? in
        let label = action.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = action.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty || prompt.isEmpty { return nil }
        return CoachQuickAction(label: label, prompt: prompt)
    }
    var seen = Set<String>()
    var deduplicated: [CoachQuickAction] = []
    for action in cleaned where seen.insert(action.prompt).inserted {
        deduplicated.append(action)
    }
    return Array(deduplicated.prefix(3))
}

func buildCoachReplyQuickActions(message: CoachChatMessage, digest: CoachDailyDigest?, training: DailyTrainingState) -> [CoachReplyQuickAction] {
    guard message.role == .assistant else { return [] }
    let normalizedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let focusPoint = digest?.focusAreas.first?.point ?? ""
    let focusLabel = focusPoint.isEmpty ? "这块" : focusPoint
    let activeRound = training.currentRound

    var actions: [CoachReplyQuickAction]
    if training.isActive && training.phase == .awaitingAnswer {
        actions = [
            CoachReplyQuickAction(label: "先给我一点提示", prompt: "先别直接给答案。请只提醒我这题第一步该看什么，再给我一个很小的提示。"),
            CoachReplyQuickAction(label: "这题在考什么", prompt: "这道题本质上在考我什么？请只说核心考点和判断入口，不要直接展开完整解答。"),
            CoachReplyQuickAction(
                label: "换一道同类题",
                prompt: activeRound.map { round in
                    "把当前这道先放下，再给我一道和「\(round.title)」同方向、但更容易一点的题，先只给题目不要答案。"
                } ?? "再给我一道同方向但更容易一点的题，先只给题目不要答案。"
            )
        ]
    } else if normalizedText.contains("错因") || normalizedText.contains("漏掉") || normalizedText.contains("知识点") {
        actions = [
            CoachReplyQuickAction(label: "再分析其他漏洞", prompt: "除了你刚才说的这个点，再帮我排查一下我还有没有第二个容易漏掉的漏洞。请按轻重缓急说。"),
            CoachReplyQuickAction(
                label: "帮我出一道题",
                prompt: focusPoint.isEmpty
                    ? "根据你刚才的分析，马上给我出一道最能暴露问题的典型题，先不要答案。"
                    : "围绕「\(focusPoint)」马上给我出一道典型题，先不要答案，等我作答后你再批改。"
            ),
            CoachReplyQuickAction(label: "给我一个检查顺序", prompt: "把你刚才说的内容压缩成一个很短的检查顺序，我下次做题时可以直接照着过一遍。")
        ]
    } else {
        actions = [
            CoachReplyQuickAction(
                label: "帮我出一道题",
                prompt: focusPoint.isEmpty
                    ? "根据你刚才的分析给我出一道题，先不要答案，等我作答后你再批改。"
                    : "围绕「\(focusLabel)」给我出一道典型题，先不要答案，等我作答后你再批改。"
            ),
            CoachReplyQuickAction(label: "再分析分析其他", prompt: "在刚才那段分析之外，再帮我看看我还有没有别的薄弱点，尤其是容易被我忽略的那种。"),
            CoachReplyQuickAction(label: "说具体一点", prompt: "把你刚才的判断再说具体一点：到底是哪一步最容易出问题？我第一眼应该先检查什么？")
        ]
    }

    let cleaned = actions.compactMap { action -> CoachReplyQuickAction? in
        let label = action.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = action.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty || prompt.isEmpty { return nil }
        return CoachReplyQuickAction(label: label, prompt: prompt)
    }
    var seen = Set<String>()
    var deduplicated: [CoachReplyQuickAction] = []
    for action in cleaned where seen.insert(action.prompt).inserted {
        deduplicated.append(action)
    }
    return Array(deduplicated.prefix(3))
}

func buildCoachRecommendationFollowupPrompt(_ question: CoachRecommendedQuestion) -> String {
    let title = question.title.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { "这道推荐题" }
    let reason = normalizeCoachSentence(question.reason)
    let basis = normalizeCoachSentence(question.basis)
    var output = "你为什么今天推荐我练「\(title)」？请直接说清它对应我的哪个漏洞，并提醒我做这类题第一眼先看什么。"
    if !reason.isEmpty {
        output += "你之前给的理由是：\(reason)。"
    }
    if !basis.isEmpty {
        output += "出题依据是：\(basis)。"
    }
    return output
}

func buildCoachTrainingPrompt(_ digest: CoachDailyDigest?) -> String {
    let firstRecommended = digest?.recommendedQuestions.first?.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !firstRecommended.isEmpty { return firstRecommended }
    let focusSummary = (digest?.focusAreas ?? []).prefix(3).map { $0.point }.joined(separator: "、").ifBlank { "当前最需要排查的薄弱点" }
    return "请根据我今天的学习情况，先给我一道围绕“\(focusSummary)”的典型题，先不要答案；等我作答后再批改，并指出我漏掉的知识点和错因。"
}

func buildCoachTrainingRounds(_ digest: CoachDailyDigest?) -> [CoachRecommendedQuestion] {
    let recommended = digest?.recommendedQuestions ?? []
    if recommended.count >= 3 { return Array(recommended.prefix(3)) }

    var generated: [CoachRecommendedQuestion] = []
    var existingPrompts = Set(recommended.map { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) })
    let dateKey = (digest?.dateKey ?? "").ifBlank { currentCoachDateKey() }

    if let focusAreas = digest?.focusAreas {
        for (index, area) in focusAreas.enumerated() {
            if generated.count + recommended.count >= 3 { continue }
            let prompt = "请给我一道围绕“\(area.point)”的典型训练题，先只给题目，不要答案；等我作答后再批改，并指出我在\(area.point)上最容易漏掉的知识点。"
            if existingPrompts.insert(prompt).inserted {
                generated.append(CoachRecommendedQuestion(
                    id: "coach-round-\(dateKey)-\(index)-\(area.point.hashValue)",
                    title: "\(area.point) · 加练",
                    reason: area.diagnosis,
                    prompt: prompt,
                    basis: buildCoachRecommendationBasis(area: area, anchor: nil, actionHint: normalizeCoachSentence(area.action))
                ))
            }
        }
    }

    while generated.count + recommended.count < 3 {
        let index = generated.count + recommended.count
        let prompt: String
        if index == 0 {
            prompt = buildCoachTrainingPrompt(digest)
        } else {
            prompt = "请给我一道中等难度典型题，先只给题目不要答案；等我作答后再批改，并明确指出我漏掉的知识点和错因。"
        }
        if existingPrompts.insert(prompt.trimmingCharacters(in: .whitespacesAndNewlines)).inserted {
            generated.append(CoachRecommendedQuestion(
                id: "coach-round-\(dateKey)-generic-\(index)",
                title: "综合训练 · 第\(index + 1)题",
                reason: "补足今天的完整训练轮次。",
                prompt: prompt,
                basis: "用于补足今天的训练闭环，继续验证你当前最容易漏掉的判断点。"
            ))
        } else {
            break
        }
    }

    return Array((recommended + generated).prefix(3))
}

func buildTrainingRoundDisplayText(round: CoachRecommendedQuestion, roundIndex: Int, totalRounds: Int) -> String {
    let title = round.title.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { "典型题" }
    return "今日训练 · 第\(roundIndex + 1)/\(totalRounds)题 · \(title)"
}

func buildTrainingEvaluationPrompt(round: CoachRecommendedQuestion, trainingQuestion: String, studentAnswer: String) -> String {
    let normalizedQuestion = trainingQuestion.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank { "（题目文本缺失，请先基于下方作答意图尽量批改）" }
    let normalizedAnswer = studentAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = round.title.ifBlank { "典型题训练" }
    return """
    你刚才给我的训练题如下，请直接开始批改。

    【训练主题】
    \(title)

    【原题】
    \(normalizedQuestion)

    【我的作答】
    \(normalizedAnswer)

    请按下面结构输出，简洁直接：
    1. 结论：正确 / 部分正确 / 错误
    2. 我真正漏掉的知识点
    3. 关键错因（为什么会错）
    4. 下一步怎么改
    5. 一句过关判断

    要求：
    - 先指出最核心的问题，不要空话；
    - 除非我整体思路都错了，否则不要展开很长的完整题解；
    - 过关判断里如果可以进入下一题，请明确写“可以进入下一题”。
    """
}

// MARK: - Private helpers

private func buildCoachDigestSummary(focusAreas: [CoachFocusArea], practiceCount: Int, savedCount: Int) -> String {
    if focusAreas.isEmpty {
        if practiceCount == 0 && savedCount == 0 {
            return "今天还没有足够样本。先做2到3道题，最好带上你的作答过程，我会更容易抓到你真正漏掉的知识点。"
        }
        return "你目前没有出现特别集中的漏洞。继续做题时，尽量把“为什么这样做”和“哪里不懂”说清楚，我会更快定位你的卡点。"
    }
    let lead = focusAreas.first!
    let extra = focusAreas.dropFirst().map { $0.point }.joined(separator: "、")
    var output = "结合今天\(max(practiceCount, 0))次提问"
    if savedCount > 0 {
        output += "和\(savedCount)道收藏题"
    }
    output += "来看，你最该先补的是“\(lead.point)”。\(lead.diagnosis)"
    if !extra.isEmpty {
        output += "其次再看\(extra)。"
    }
    output += "今天的练法就按“先判断、再步骤、最后复盘知识点”的顺序来。"
    return output
}

private func buildCoachRecommendedQuestions(focusAreas: [CoachFocusArea], savedQuestions: [SavedQuestion], nowMillis: Int64) -> [CoachRecommendedQuestion] {
    if focusAreas.isEmpty {
        return [
            CoachRecommendedQuestion(
                id: "coach-rec-\(nowMillis)-0",
                title: "通用回测题",
                reason: "先给我一道题做样本，教练才能更快定位薄弱点。",
                prompt: "请给我一道适合我当前年级的中等难度典型题，先不要答案，等我作答后再批改，并指出我漏掉的知识点。",
                basis: "当前样本还不够，所以先用一题通用回测题快速补齐样本。",
                anchorSavedQuestionId: nil
            ),
            CoachRecommendedQuestion(
                id: "coach-rec-\(nowMillis)-1",
                title: "思路判断题",
                reason: "先测我是不是会选切入点，而不只是会套步骤。",
                prompt: "请给我一道需要先判断切入点的典型题，先只给题目，不要答案；等我作答后重点评价我的思路是否正确。",
                basis: "当前先优先排查你是不是卡在切入点判断，而不是只会套步骤。",
                anchorSavedQuestionId: nil
            )
        ]
    }

    return focusAreas.prefix(3).enumerated().map { (index, area) -> CoachRecommendedQuestion in
        let anchor = selectCoachAnchorQuestion(point: area.point, savedQuestions: savedQuestions)
        let difficultyHint: String
        switch area.level {
        case .high: difficultyHint = "基础到中档"
        case .medium: difficultyHint = "中档"
        case .low: difficultyHint = "入门到中档"
        }
        let actionHint = normalizeCoachSentence(area.action)
        let title = "\(area.point) · 典型题"
        let reason: String
        if let saved = anchor {
            reason = "参考你之前卡住的题《\(normalizeCoachSnippet(saved.question, 16))》：\(area.diagnosis)"
        } else {
            reason = area.diagnosis
        }
        var prompt = "请给我一道围绕“\(area.point)”的\(difficultyHint)典型题，重点训练：\(actionHint)。先只给题目，不要答案；等我作答后再批改，并指出我漏掉的知识点。"
        if let saved = anchor {
            prompt += "可以参考我之前容易错的方向：\(normalizeCoachSnippet(saved.question, 28))。"
        }
        return CoachRecommendedQuestion(
            id: "coach-rec-\(nowMillis)-\(index)-\(area.point.hashValue)",
            title: title,
            reason: reason,
            prompt: prompt,
            basis: buildCoachRecommendationBasis(area: area, anchor: anchor, actionHint: actionHint),
            anchorSavedQuestionId: anchor?.id
        )
    }
}

private func buildCoachRecommendationBasis(area: CoachFocusArea, anchor: SavedQuestion?, actionHint: String) -> String {
    let anchorSnippet = anchor?.question.flatMap { normalizeCoachSnippet($0, 18) } ?? ""
    var output = "这道题主要围绕“\(area.point)”，因为你今天最集中暴露的问题是：\(normalizeCoachSentence(area.diagnosis))。"
    if !actionHint.isEmpty {
        output += "训练重点放在：\(actionHint)。"
    }
    if !anchorSnippet.isEmpty {
        output += "并参考你之前卡住的依据题《\(anchorSnippet)》。"
    }
    return output
}

private func selectCoachAnchorQuestion(point: String, savedQuestions: [SavedQuestion]) -> SavedQuestion? {
    let candidates = savedQuestions.filter { saved in
        saved.knowledgeTags.contains(point) ||
            inferKnowledgePoints([saved.question, saved.answer].joined(separator: "\n")).contains(point)
    }
    return candidates.sorted { lhs, rhs in
        if lhs.followupCount != rhs.followupCount { return lhs.followupCount > rhs.followupCount }
        return lhs.savedAt > rhs.savedAt
    }.first
}

private func buildCoachContextText(
    digest: CoachDailyDigest?,
    profile: ProfileState,
    knowledgePoints: [String: Int],
    knowledgeGapInsights: [KnowledgeGapInsight],
    savedQuestions: [SavedQuestion]
) -> String {
    let topKnowledge = knowledgePoints
        .sorted { $0.value > $1.value }
        .prefix(5)
        .map { "\($0.key)\($0.value)次" }
        .joined(separator: "、")
        .ifBlank { "暂无" }

    let gapSummary = knowledgeGapInsights.prefix(3).map { insight in
        "- \(insight.point)（\(insight.level.label)）：\(normalizeCoachText(insight.diagnosis))；建议 \(normalizeCoachSentence(insight.action))"
    }.joined(separator: "\n").ifBlank { "- 暂无明显集中薄弱点" }

    let savedSummary = savedQuestions.prefix(3).map { saved in
        "- \(normalizeCoachSnippet(saved.question, 26))"
    }.joined(separator: "\n").ifBlank { "- 暂无收藏题" }

    let digestSummary: String
    if let current = digest {
        digestSummary = "\(current.headline)；\(normalizeCoachText(current.summary))"
    } else {
        digestSummary = "今日教练总结暂未生成"
    }

    return """
    以下是学生的学习画像，只作背景参考，不要逐条复述：
    - 当前阶段：\(profile.level)
    - 高频知识点：\(topKnowledge)
    - 今日教练总结：\(digestSummary)
    - 当前薄弱点：
    \(gapSummary)
    - 最近收藏题：
    \(savedSummary)

    请你像学习教练一样回答：
    1. 先指出最核心的问题；
    2. 再给1到3条可执行建议；
    3. 如果适合，就顺手安排一个很小的判断练习或复盘动作；
    4. 保持简洁，不要空话。
    """
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        return isEmpty ? fallback : self
    }
}
