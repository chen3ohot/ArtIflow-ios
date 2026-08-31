import Foundation

func currentTimeMillis() -> Int64 {
    return Int64(Date().timeIntervalSince1970 * 1000)
}

func nowTimeString() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: Date())
}

func currentCoachDateKey(nowMillis: Int64 = currentTimeMillis()) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(nowMillis) / 1000.0)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

func formatTimestamp(_ millis: Int64, format: String) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = format
    return formatter.string(from: date)
}

/// 卡片下次复习时间格式化（用于复习 toast）
func formatSessionTime(_ millis: Int64) -> String {
    return formatTimestamp(millis, format: "MM-dd HH:mm")
}

func normalizeInlineText(_ text: String) -> String {
    return text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func normalizeCardText(_ text: String, maxLen: Int) -> String {
    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty { return "" }

    let trimmedLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespaces) }

    var collapsed = ""
    var pendingBlank = 0
    for line in trimmedLines {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingBlank += 1
            continue
        }
        if !collapsed.isEmpty {
            let blanksToInsert = min(max(pendingBlank, 1), 2)
            collapsed += String(repeating: "\n", count: blanksToInsert)
        }
        pendingBlank = 0
        collapsed += line
    }
    let result = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(result.prefix(maxLen))
}

func buildSessionTitle(_ messages: [ChatMessage], fallbackTime: String) -> String {
    for message in messages {
        if case .user(_, _, let text, _, _) = message {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(18))
            }
        }
    }
    return "新会话 \(fallbackTime)"
}
