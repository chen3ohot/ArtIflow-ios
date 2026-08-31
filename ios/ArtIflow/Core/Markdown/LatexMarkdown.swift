import Foundation

// MARK: - LaTeX detection / normalization (StudyChatMarkdown.kt)
// Faithful port of the Android regex-based LaTeX marker detection and normalization,
// so iOS-rendered Markdown stays compatible with the assistant's formula output.

let markdownBulletPattern = "^[-*+]\\s+"
let markdownOrderedPattern = "^(\\d+)\\.\\s+"

// (?s)(^|\n)\$\$\s*.+?\s*\$\$($|\n)
let markdownDoubleDollarBlockPattern = "(?s)(^|\\n)\\$\\$\\s*.+?\\s*\\$\\$($|\\n)"
// (?<!\\)\$\$[^\n]+?\$\$
let markdownDoubleDollarInlinePattern = "(?<!\\\\)\\$\\$[^\\n]+?\\$\\$"
// (?<!\\)(?<!\$)\$([^$\n]+)\$(?!\$)
let markdownSingleDollarInlinePattern = "(?<!\\\\)(?<!\\$)\\$([^$\\n]+)\\$(?!\\$)"
// (?s)\\\[\s*(.+?)\s*\\\]
let markdownBracketBlockPattern = "(?s)\\\\\\[\\s*(.+?)\\s*\\\\\\]"
// (?s)\\\((.+?)\\\)
let markdownParenInlinePattern = "(?s)\\\\\\((.+?)\\\\\\)"

private func makeRegex(_ pattern: String) -> NSRegularExpression {
    // swiftlint:disable:next force_try
    return try! NSRegularExpression(pattern: pattern, options: [])
}

private func containsMatch(_ pattern: String, in string: String) -> Bool {
    let regex = makeRegex(pattern)
    let range = NSRange(string.startIndex..., in: string)
    return regex.firstMatch(in: string, range: range) != nil
}

private func captureGroup(_ string: String, match: NSTextCheckingResult, group: Int) -> String? {
    let nsRange = match.range(at: group)
    if nsRange.location == NSNotFound { return nil }
    guard let range = Range(nsRange, in: string) else { return nil }
    return String(string[range])
}

private func replaceMatches(_ pattern: String, in string: String, using transform: (NSTextCheckingResult) -> String) -> String {
    let regex = makeRegex(pattern)
    var result = ""
    var lastEnd = string.startIndex
    let range = NSRange(string.startIndex..., in: string)
    regex.enumerateMatches(in: string, range: range) { match, _, _ in
        guard let match = match,
              let matchRange = Range(match.range, in: string) else { return }
        result += String(string[lastEnd..<matchRange.lowerBound])
        result += transform(match)
        lastEnd = matchRange.upperBound
    }
    result += String(string[lastEnd...])
    return result
}

func containsLatexMarkdown(_ markdown: String) -> Bool {
    if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    return containsMatch(markdownDoubleDollarBlockPattern, in: markdown) ||
        containsMatch(markdownDoubleDollarInlinePattern, in: markdown) ||
        containsMatch(markdownBracketBlockPattern, in: markdown) ||
        containsMatch(markdownParenInlinePattern, in: markdown) ||
        containsMatch(markdownSingleDollarInlinePattern, in: markdown)
}

func normalizeLatexForMarkwon(_ markdown: String) -> String {
    if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return markdown }

    var normalized = normalizeIndentedBracketBlocks(markdown)

    normalized = replaceMatches(markdownBracketBlockPattern, in: normalized) { match in
        let equation = (captureGroup(normalized, match: match, group: 1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "$$\n\(equation)\n$$"
    }

    normalized = replaceMatches(markdownParenInlinePattern, in: normalized) { match in
        let equation = (captureGroup(normalized, match: match, group: 1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "$$" + equation + "$$"
    }

    normalized = replaceMatches(markdownSingleDollarInlinePattern, in: normalized) { match in
        let equation = captureGroup(normalized, match: match, group: 1) ?? ""
        return "$$" + equation + "$$"
    }

    return normalized
}

private func normalizeIndentedBracketBlocks(_ markdown: String) -> String {
    let normalizedSource = markdown
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalizedSource.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    if !lines.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "\\[" }) {
        return normalizedSource
    }

    var output: [String] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        if line.trimmingCharacters(in: .whitespacesAndNewlines) != "\\[" {
            output.append(line)
            index += 1
            continue
        }

        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var blockLines: [String] = []
        var cursor = index + 1
        var closed = false
        while cursor < lines.count {
            let candidate = lines[cursor]
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines) == "\\]" {
                closed = true
                break
            }
            blockLines.append(candidate)
            cursor += 1
        }

        if !closed {
            output.append(line)
            output.append(contentsOf: blockLines)
            break
        }

        output.append(indent + "$$")
        for contentLine in stripCommonIndent(blockLines) {
            output.append(contentLine.isEmpty ? indent : indent + contentLine)
        }
        output.append(indent + "$$")
        index = cursor + 1
    }

    return output.joined(separator: "\n")
}

private func stripCommonIndent(_ lines: [String]) -> [String] {
    let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if nonBlank.isEmpty { return lines }

    let commonIndent = nonBlank.map { line -> Int in
        if let firstNonBlankIndex = line.firstIndex(where: { !$0.isWhitespace }) {
            return line.distance(from: line.startIndex, to: firstNonBlankIndex)
        }
        return line.count
    }.min() ?? 0

    return lines.map { line -> String in
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        let dropped = String(line.dropFirst(commonIndent))
        return dropped.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    }
}
