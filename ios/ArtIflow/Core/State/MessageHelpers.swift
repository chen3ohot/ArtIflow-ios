import Foundation

// MARK: - Span/message lookup helpers (StudyChatModels.kt)

func findSpanById(_ messages: [ChatMessage], spanId: String?) -> SpanData? {
    guard let spanId = spanId else { return nil }
    for message in messages {
        if case .assistant = message, let found = message.findSpan(spanId) {
            return found
        }
    }
    return nil
}

func findLatestAssistantSpan(_ messages: [ChatMessage]) -> SpanData? {
    for message in messages.reversed() {
        if case .assistant(_, _, let spans, let mainSpan, _) = message {
            let span = spans.last ?? mainSpan
            if let span = span { return span }
        }
    }
    return nil
}

func findLatestAssistantQuestionSpan(_ messages: [ChatMessage]) -> SpanData? {
    for message in messages.reversed() {
        if case .assistant(_, _, let spans, let mainSpan, _) = message {
            let span = mainSpan ?? spans.last
            if let span = span { return span }
        }
    }
    return nil
}

func findDetailById(_ details: [SpanDetail], detailId: String?) -> SpanDetail? {
    guard let detailId = detailId else { return nil }
    return details.first { $0.id == detailId }
}

func buildDetailPath(_ details: [SpanDetail], detailId: String?) -> [SpanDetail] {
    guard let targetId = detailId else { return [] }
    let detailById = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
    var path: [SpanDetail] = []
    var visited = Set<String>()
    var current = detailById[targetId]

    while let currentDetail = current, visited.insert(currentDetail.id).inserted {
        path.append(currentDetail)
        if let parentId = currentDetail.parentDetailId {
            current = detailById[parentId]
        } else {
            current = nil
        }
    }

    return path.reversed()
}

// MARK: - Knowledge merging (StudyChatViewModelSupport.kt)

func mergeKnowledgePoints(_ current: [String: Int], texts: [String]) -> [String: Int] {
    var merged = current
    var points: [String] = []
    var seen = Set<String>()
    for text in texts {
        for point in canonicalizeHighSchoolKnowledgePoint(text) where !point.isEmpty {
            if seen.insert(point).inserted { points.append(point) }
        }
    }
    for point in points {
        merged[point, default: 0] += 1
    }
    return merged
}

// MARK: - Paragraph / prompt builders (StudyChatViewModelSupport.kt)

func splitParagraphs(_ content: String) -> [String] {
    let byBlankLines = content
        .split(whereSeparator: { $0 == "\n" })
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    if byBlankLines.count > 1 { return byBlankLines }

    let sentencePattern = "[^。！？!?]+[。！？!?]?"
    let sentenceRegex = makeRegex(sentencePattern)
    let nsRange = NSRange(content.startIndex..., in: content)
    var sentences: [String] = []
    sentenceRegex.enumerateMatches(in: content, range: nsRange) { match, _, _ in
        guard let match = match, let range = Range(match.range, in: content) else { return }
        sentences.append(String(content[range]))
    }
    if sentences.isEmpty {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    var chunks: [String] = []
    var current = ""
    for sentence in sentences {
        if (current + sentence).count > 54 && !current.isEmpty {
            chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            current = sentence
        } else {
            current += sentence
        }
    }
    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return chunks
}

func buildAutoExplainPrompt(_ spanContent: String) -> String {
    return "请只针对下面这一段内容做简洁讲解。输出要求：1) 用中文；2) 先1句结论；3) 再给2~3条关键点；4) 总字数尽量控制在120字内；5) 不要套话。\n\n段落内容：\(spanContent)"
}

func buildDetailCardSummary(question: String?, answer: String) -> String {
    let questionSnippet = normalizeInlineText(question ?? "").prefix(28)
    let answerSnippet = extractAnswerSnippetForSummary(answer)

    if questionSnippet.isEmpty && answerSnippet.isEmpty { return "讲解摘要" }
    if questionSnippet.isEmpty { return answerSnippet }
    if answerSnippet.isEmpty { return String(questionSnippet) }
    return "\(questionSnippet) · \(answerSnippet)"
}

private func extractAnswerSnippetForSummary(_ answer: String) -> String {
    var plain = answer
    plain = plain.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
    plain = plain.replacingOccurrences(of: "[#>*`_\\[\\]()|]", with: " ", options: .regularExpression)
    plain = normalizeInlineText(plain)
    if plain.isEmpty { return "" }

    let firstSentenceRegex = makeRegex("[^。！？!?；;]{1,54}[。！？!?；;]?")
    let nsRange = NSRange(plain.startIndex..., in: plain)
    var firstSentence = ""
    if let match = firstSentenceRegex.firstMatch(in: plain, range: nsRange),
       let range = Range(match.range, in: plain) {
        firstSentence = String(plain[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return firstSentence.isEmpty ? String(plain.prefix(54)) : String(firstSentence.prefix(54))
}

func buildSavedQuestionPreview(_ answer: String) -> String {
    let snippet = extractAnswerSnippetForSummary(answer)
    if !snippet.isEmpty { return snippet }
    return String(normalizeInlineText(answer).prefix(56))
}

func buildFollowupTreeAnswerPreview(_ answer: String) -> String {
    let normalized = normalizeInlineText(answer)
    if normalized.isEmpty { return "（无回答内容）" }
    return normalized.count <= 160 ? normalized : String(normalized.prefix(160)) + "..."
}

func buildFollowupTreeExportFileName(exportedAtMillis: Int64 = currentTimeMillis()) -> String {
    let timestamp = formatTimestamp(exportedAtMillis, format: "yyyyMMdd-HHmmss")
    return "追问图谱-\(timestamp).md"
}

func buildFollowupTreeExportMarkdown(_ scopes: [FollowupTreeScope], exportedAtMillis: Int64 = currentTimeMillis()) -> String {
    if scopes.isEmpty { return "暂无追问图谱可导出。" }
    let exportedAt = formatTimestamp(exportedAtMillis, format: "yyyy-MM-dd HH:mm")
    let nodeCount = scopes.reduce(0) { $0 + $1.details.count }

    var output = "# 追问图谱导出\n\n"
    output += "- 导出时间：\(exportedAt)\n"
    output += "- 段落数：\(scopes.count)\n"
    output += "- 追问节点数：\(nodeCount)\n"

    for (index, scope) in scopes.enumerated() {
        let normalizedSpanContent = normalizeInlineText(scope.spanContent)
        let normalizedSourceQuestion = normalizeInlineText(scope.sourceQuestion)
        output += "\n## 段落 \(index + 1)\n"
        output += "- 段落ID：\(scope.spanId)\n"
        output += "- 段落内容：\(normalizedSpanContent.isEmpty ? "（空）" : normalizedSpanContent)\n"
        output += "- 来源问题：\(normalizedSourceQuestion.isEmpty ? "（空）" : normalizedSourceQuestion)\n"

        if scope.details.isEmpty {
            output += "- 追问节点：暂无\n"
            continue
        }
        output += "- 追问节点：\n"
        for (depth, detail) in buildFollowupTreeExportEntries(scope.details) {
            let indent = String(repeating: "  ", count: depth)
            let summary = detail.summary?.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isEmpty } ?? buildDetailCardSummary(question: detail.question, answer: detail.answer)
            output += "  \(indent)- \(detail.mode) · \(detail.time)\n"
            output += "  \(indent)  - 问题：\(normalizeInlineText(detail.question ?? "").isEmpty ? "（无问题文本）" : normalizeInlineText(detail.question ?? ""))\n"
            output += "  \(indent)  - 摘要：\(normalizeInlineText(summary).isEmpty ? "讲解摘要" : normalizeInlineText(summary))\n"
            output += "  \(indent)  - 回答预览：\(buildFollowupTreeAnswerPreview(detail.answer))\n"
            if let parentId = detail.parentDetailId, !parentId.isEmpty {
                output += "  \(indent)  - 父节点：\(parentId)\n"
            }
        }
    }
    return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
}

private func buildFollowupTreeExportEntries(_ details: [SpanDetail]) -> [(Int, SpanDetail)] {
    if details.isEmpty { return [] }
    let chronological = details.reversed()
    let allIds = Set(chronological.map { $0.id })
    var childrenByParent: [String?: [SpanDetail]] = [:]
    var parentOrder: [String?] = []
    for detail in chronological {
        let normalizedParent = detail.parentDetailId.flatMap { allIds.contains($0) ? $0 : nil }
        if childrenByParent[normalizedParent] == nil { parentOrder.append(normalizedParent) }
        childrenByParent[normalizedParent, default: []].append(detail)
    }

    var flattened: [(Int, SpanDetail)] = []
    var visited = Set<String>()

    func appendNode(_ detail: SpanDetail, depth: Int, lineage: Set<String>) {
        if lineage.contains(detail.id) || !visited.insert(detail.id).inserted { return }
        flattened.append((depth, detail))
        let nextLineage = lineage.union([detail.id])
        for child in childrenByParent[detail.id] ?? [] {
            appendNode(child, depth: depth + 1, lineage: nextLineage)
        }
    }

    let roots = childrenByParent[nil] ?? chronological
    for root in roots { appendNode(root, depth: 0, lineage: []) }
    for detail in chronological where !visited.contains(detail.id) {
        appendNode(detail, depth: 0, lineage: [])
    }
    return flattened
}

private func makeRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
    // swiftlint:disable:next force_try
    return try! NSRegularExpression(pattern: pattern, options: options)
}

// MARK: - Ark message building (StudyChatViewModelSupport.kt)

func toArkMessages(_ messages: [ChatMessage]) -> [ArkRequestMessage] {
    let filtered = messages.filter { message in
        if case .assistant(_, _, let spans, let mainSpan, _) = message {
            let sourceQuestion = mainSpan?.sourceQuestion ?? spans.first?.sourceQuestion
            return sourceQuestion != "初始化引导"
        }
        return true
    }
    return Array(filtered.suffix(12).compactMap { message -> ArkRequestMessage? in
        switch message {
        case .user(_, _, let text, _, _):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : ArkRequestMessage(role: "user", text: trimmed)
        case .assistant:
            let text = message.fullAnswerText()
            return text.isEmpty ? nil : ArkRequestMessage(role: "assistant", text: text)
        }
    })
}

func toSpanFollowupMessages(span: SpanData, followupQuestion: String, details: [SpanDetail], messages: [ChatMessage] = []) -> [ArkRequestMessage] {
    let recentDetails = Array(details.prefix(4).reversed())
    let sourceQuestion = resolveQuestionScopeQuestion(span: span, messages: messages)
    let questionScopeAnswer = resolveQuestionScopeAnswer(spanId: span.id, messages: messages)
    var contextMessage = "我们以题目为单位回答追问，请先阅读完整上下文再作答。\n"
    contextMessage += "回答要求：简洁直接，先结论后要点，默认不超过6行。\n"
    contextMessage += "题目："
    contextMessage += sourceQuestion.isEmpty ? "（原题缺失，请结合上下文回答）" : sourceQuestion
    if !questionScopeAnswer.isEmpty {
        contextMessage += "\n该题完整回答："
        contextMessage += questionScopeAnswer
    }
    contextMessage += "\n当前追问聚焦段落："
    contextMessage += span.content

    var result: [ArkRequestMessage] = [ArkRequestMessage(role: "user", text: contextMessage)]
    for detail in recentDetails {
        if let question = detail.question, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(ArkRequestMessage(role: "user", text: question))
        }
        let answer = detail.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty {
            result.append(ArkRequestMessage(role: "assistant", text: answer))
        }
    }
    result.append(ArkRequestMessage(role: "user", text: followupQuestion))
    return result
}

private func resolveQuestionScopeAnswer(spanId: String, messages: [ChatMessage]) -> String {
    for message in messages {
        if case .assistant = message, message.findSpan(spanId) != nil {
            return message.fullAnswerText()
        }
    }
    return ""
}

private func resolveQuestionScopeQuestion(span: SpanData, messages: [ChatMessage]) -> String {
    let sourceAssistantIndex = messages.firstIndex(where: { $0.findSpan(span.id) != nil })
    if let index = sourceAssistantIndex, case .assistant = messages[index] {
        if let sourceSpanQuestion = messages[index].findSpan(span.id)?.sourceQuestion.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceSpanQuestion.isEmpty {
            return sourceSpanQuestion
        }
    }
    let fallbackSpanQuestion = span.sourceQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    if !fallbackSpanQuestion.isEmpty { return fallbackSpanQuestion }

    if let index = sourceAssistantIndex, index > 0 {
        for i in stride(from: index - 1, through: 0, by: -1) {
            if case .user(_, _, let text, _, _) = messages[i] {
                let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !question.isEmpty { return question }
            }
        }
    }
    return ""
}

// MARK: - Token / error helpers (StudyChatViewModelSupport.kt)

func isTokenStale(requestToken: Int64, activeToken: Int64) -> Bool {
    return requestToken != activeToken
}

func extractFencedJsonCandidate(_ raw: String) -> String? {
    let pattern = "```(?:json)?\\s*(\\{.*?\\})\\s*```"
    let regex = makeRegex(pattern, options: [.dotMatchesLineSeparators])
    let nsRange = NSRange(raw.startIndex..., in: raw)
    guard let match = regex.firstMatch(in: raw, range: nsRange),
          let range = Range(match.range(at: 1), in: raw) else { return nil }
    return String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
}

func resolveErrorHint(_ throwable: Error?, fallback: String) -> String {
    guard let throwable = throwable else { return fallback }
    if let hint = resolveNetworkErrorHint(throwable) { return hint }
    let message = (throwable.localizedDescription).trimmingCharacters(in: .whitespacesAndNewlines)
    return message.isEmpty ? fallback : String(message.prefix(80))
}

private func resolveNetworkErrorHint(_ error: Error) -> String? {
    let nsError = error as NSError
    let messages = [error.localizedDescription] + causeChain(error).map { $0.localizedDescription }
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
        return "网络超时，请稍后重试"
    }
    if nsError.domain == NSURLErrorDomain, [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid, NSURLErrorServerCertificateHasUnknownRoot].contains(nsError.code) {
        return "证书校验失败；如果你连的是自建 IP 接口，请把 BASEURL 改成 http://IP:端口/v1"
    }
    let lowered = messages.map { $0.lowercased() }
    if lowered.contains(where: { $0.contains("certificate") || $0.contains("hostname") || $0.contains("trust") || $0.contains("peer not verified") }) {
        return "证书校验失败；如果你连的是自建 IP 接口，请把 BASEURL 改成 http://IP:端口/v1"
    }
    if lowered.contains(where: { $0.contains("software caused connection abort") || $0.contains("connection reset") || $0.contains("connection aborted") || $0.contains("broken pipe") || $0.contains("unexpected end of stream") || $0.contains("network connection lost") }) {
        return "网络连接中断，请重试"
    }
    return nil
}

private func causeChain(_ error: Error, maxDepth: Int = 8) -> [Error] {
    // NSError does not expose a structured cause; surface only the root error.
    return [error]
}

func routeRequestFailure(throwable: Error, fallback: String = "网络不可用", onCancel: () -> Void = {}, onError: (String) -> Void) {
    if throwable is CancellationError {
        onCancel()
        return
    }
    onError(resolveErrorHint(throwable, fallback: fallback))
}

func deliverTokenAwareResult<T>(
    result: Result<T, Error>,
    requestToken: Int64,
    activeToken: Int64,
    onStale: () -> Void,
    onSuccess: (T) -> Void,
    onFailure: (Error) -> Void
) {
    if isTokenStale(requestToken: requestToken, activeToken: activeToken) {
        onStale()
        return
    }
    switch result {
    case .success(let value): onSuccess(value)
    case .failure(let error): onFailure(error)
    }
}

// MARK: - Image / archive helpers (StudyChatViewModelSupport.kt)

func isGenericImageSearchQuestion(_ text: String) -> Bool {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty { return false }
    return normalized.hasPrefix("拍照搜题：") || normalized.hasPrefix("相册搜题：") || normalized.hasPrefix("多图搜题：")
}

func buildFallbackSavedQuestionTitle(sourceQuestion: String, answer: String) -> String {
    if let candidate = sourceQuestion.trimmingCharacters(in: .whitespacesAndNewlines).trimOrNull(), !isGenericImageSearchQuestion(candidate) {
        return normalizeCardText(candidate, maxLen: 120)
    }
    let normalizedAnswer = normalizeCardText(answer, maxLen: 180)
    let candidateLine = normalizedAnswer
        .split(whereSeparator: { $0 == "\n" })
        .map { line -> String in
            var s = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            while let first = s.first, "#-*•、：: ".contains(first) || first.isNumber || first == "." {
                s.removeFirst()
            }
            return s
        }
        .first(where: { $0.count >= 8 }) ?? ""
    return String(candidateLine.prefix(120)).isEmpty ? "图片题目归档" : String(candidateLine.prefix(120))
}

func buildFallbackImageArchivePayload(sourceQuestion: String, answer: String) -> ImageQuestionArchivePayload {
    let question = buildFallbackSavedQuestionTitle(sourceQuestion: sourceQuestion, answer: answer)
    let combinedText = [question, answer].joined(separator: "\n")
    let tagged = QuestionTagger.autoTag(combinedText)
    let knowledgeTags = filterToHighSchoolKnowledgeTags(tagged.knowledgePoints.isEmpty ? inferKnowledgePoints(combinedText) : tagged.knowledgePoints, maxSize: 6)
    let summary = normalizeCardText(answer, maxLen: 120)
        .split(whereSeparator: { $0 == "\n" })
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { $0.count >= 10 }) ?? ""
    return ImageQuestionArchivePayload(
        question: question,
        subject: tagged.subject == "其他" ? "" : tagged.subject,
        questionType: tagged.questionType == "其他" ? "" : tagged.questionType,
        knowledgeTags: knowledgeTags,
        analysisSummary: summary
    )
}

func buildImageQuestionArchivePrompt(sourcePrompt: String, assistantAnswer: String) -> String {
    let promptSnippet = normalizeCardText(sourcePrompt, maxLen: 120)
    let answerSnippet = normalizeCardText(assistantAnswer, maxLen: 1600)
    var output = "你要把一道拍照题归档成结构化记录。请直接从题目图片中提取题干，并结合下方讲解提炼归档信息。\n"
    output += "\n仅输出JSON，不要代码块，不要解释。"
    output += "\nJSON格式：{\"question\":\"...\",\"subject\":\"数学/物理/化学/英语/语文/其他\",\"question_type\":\"...\",\"knowledge_tags\":[\"...\"],\"analysis_summary\":\"...\"}"
    output += "\n要求：\n1. question 直接提取原题题干，尽量完整，不要写“拍照搜题”这类系统字样；"
    output += "\n2. subject 优先判断是否属于高中学科，只允许 数学/物理/化学/英语/语文/其他；"
    output += "\n3. question_type 用简短中文，如 选择题/填空题/解答题/实验题/阅读题/作文题/其他；"
    output += "\n4. knowledge_tags 只保留高中学科知识点或学科名，最多6个；"
    output += "\n5. analysis_summary 用1到2句总结这道题主要考什么、最容易卡在哪里。"
    if !promptSnippet.isEmpty {
        output += "\n\n用户补充说明：\(promptSnippet)"
    }
    output += "\n\n已有讲解：\(answerSnippet)"
    return output
}

func parseImageQuestionArchivePayload(_ raw: String) -> ImageQuestionArchivePayload? {
    guard let payload = parseJsonObjectSafely(raw) else { return nil }
    let question = normalizeCardText(optString(payload, key: "question"), maxLen: 300)
    let subject = optString(payload, key: "subject").trimmingCharacters(in: .whitespacesAndNewlines)
    let questionType = optString(payload, key: "question_type").trimmingCharacters(in: .whitespacesAndNewlines)
    let knowledgeTags = filterToHighSchoolKnowledgeTags(
        (optArray(payload, key: "knowledge_tags") ?? []).map { optString($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
        maxSize: 6
    )
    let analysisSummary = normalizeCardText(optString(payload, key: "analysis_summary"), maxLen: 180)
    if question.isEmpty { return nil }
    return ImageQuestionArchivePayload(question: question, subject: subject, questionType: questionType, knowledgeTags: knowledgeTags, analysisSummary: analysisSummary)
}

func buildAnkiGenerationPrompt(
    mode: String,
    spanContent: String,
    question: String?,
    answer: String,
    profile: ProfileState,
    knowledgePoints: [String: Int],
    knowledgeGapInsights: [KnowledgeGapInsight],
    existingDecks: [String]
) -> String {
    let topTopics = profile.topicHits
        .sorted { $0.value > $1.value }
        .prefix(4)
        .map { "\($0.key)(\($0.value))" }
        .joined(separator: "，")
        .ifBlank { "暂无" }
    let topKnowledge = knowledgePoints
        .sorted { $0.value > $1.value }
        .prefix(6)
        .map { "\($0.key)(\($0.value))" }
        .joined(separator: "，")
        .ifBlank { "暂无" }
    let deckCatalog = existingDecks
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .deduplicated()
        .joined(separator: "，")
        .ifBlank { "暂无" }
    let gapSummary = summarizeKnowledgeGapInsights(knowledgeGapInsights)

    var output = "请根据下面学习交互，生成1张最合适的Anki卡片。"
    output += "不要套固定模板，请自行判断卡型（概念/对比/因果/步骤/易错点/例题等）。"
    output += "要求：front可直接测验、back简洁准确、不要套话。如本次内容不适合制卡，返回 skip=true。"
    output += "需要输出 deck 字段：优先归入已有卡组；只有都不匹配时再创建新卡组名。"
    output += "\n仅输出JSON，不要代码块，不要解释。"
    output += "\nJSON格式：{\"skip\":false,\"front\":\"...\",\"back\":\"...\",\"tags\":[\"...\"],\"deck\":\"...\",\"card_type\":\"...\"}"
    output += "\n约束：front<=60字，back<=180字，tags<=6。"
    output += "\ntags要求：只允许填写高中学科知识点或学科名；不要写审题、方法、不会、易错、套路、总结这类泛标签。"
    output += "\ndeck要求：只有在确实对应高中学科或知识点时才创建新卡组，否则优先复用已有卡组或归入未分类。"
    output += "\ndeck命名：2~12字，中文优先，不要使用\"卡组\"、\"默认\"这类空泛名称。"
    output += "\n\n交互模式：\(mode)"
    output += "\n用户画像热点：\(topTopics)"
    output += "\n知识点热度：\(topKnowledge)"
    output += "\n薄弱点洞察：\(gapSummary)"
    output += "\n已有卡组：\(deckCatalog)"
    output += "\n段落内容：\(spanContent)"
    if let question = question, !question.isEmpty {
        output += "\n用户追问：\(question)"
    }
    output += "\nAI回答：\(answer)"
    return output
}

func parseAiAnkiCardPayload(_ raw: String) -> AiAnkiCardPayload? {
    guard let payload = parseJsonObjectSafely(raw) else { return nil }
    if optBool(payload, key: "skip", default: false) { return nil }
    let front = optString(payload, key: "front").trimmingCharacters(in: .whitespacesAndNewlines)
    let back = optString(payload, key: "back").trimmingCharacters(in: .whitespacesAndNewlines)
    if front.isEmpty || back.isEmpty { return nil }
    let tags = filterToHighSchoolKnowledgeTags(
        (optArray(payload, key: "tags") ?? []).map { optString($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
        maxSize: 6
    )
    let deck = optString(payload, key: "deck").trimmingCharacters(in: .whitespacesAndNewlines).trimOrNull()
    return AiAnkiCardPayload(front: front, back: back, tags: tags, deck: deck)
}

func parseJsonObjectSafely(_ raw: String) -> Any? {
    let fenced = extractFencedJsonCandidate(raw)
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let bracketStart = trimmed.firstIndex(of: "{")
    let bracketEnd = trimmed.lastIndex(of: "}")
    var sliced: String? = nil
    if let start = bracketStart, let end = bracketEnd, start < end {
        sliced = String(trimmed[start...end])
    }
    var candidates: [String] = []
    if let fenced = fenced, !fenced.isEmpty { candidates.append(fenced) }
    if let sliced = sliced, !sliced.isEmpty { candidates.append(sliced) }
    if !trimmed.isEmpty { candidates.append(trimmed) }
    for candidate in candidates {
        if let parsed = JSON.parse(candidate) { return parsed }
    }
    return nil
}

func summarizeKnowledgeGapInsights(_ insights: [KnowledgeGapInsight]) -> String {
    let joined = insights.prefix(4).map { "\($0.point)(\($0.level.label))：\($0.diagnosis)" }.joined(separator: "；")
    return joined.isEmpty ? "暂无明显薄弱点" : joined
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        return isEmpty ? fallback : self
    }
}
