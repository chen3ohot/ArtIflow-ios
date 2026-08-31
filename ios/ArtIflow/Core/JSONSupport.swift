import Foundation

/// Lightweight JSON helper that mirrors the subset of Kotlin's `org.json` opt-style
/// access used by the Android persistence layer. Operating on plain `Any?` values
/// (produced by `JSONSerialization`) keeps the iOS codec byte-compatible with the
/// Android `study_suit_sessions_v1.json` format.

enum JSON {
    static func parse(_ data: Data) -> Any? {
        return try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    }

    static func parse(_ string: String) -> Any? {
        guard let data = string.data(using: .utf8) else { return nil }
        return parse(data)
    }

    static func data(_ object: Any) -> Data? {
        return try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .fragmentsAllowed]
        )
    }

    static func string(_ object: Any) -> String {
        guard let data = data(object) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - opt helpers (operate on Any?, like JSONObject.optXxx)

func optObject(_ any: Any?, key: String) -> Any? {
    guard let dict = any as? [String: Any] else { return nil }
    return dict[key]
}

func optString(_ any: Any?, key: String) -> String {
    guard let dict = any as? [String: Any], let value = dict[key] else { return "" }
    return stringValue(value)
}

func optString(_ any: Any?) -> String {
    return stringValue(any)
}

func stringValue(_ any: Any?) -> String {
    guard let value = any else { return "" }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    if value is NSNull { return "" }
    return "\(value)"
}

func optInt(_ any: Any?, key: String, default fallback: Int = 0) -> Int {
    guard let dict = any as? [String: Any], let value = dict[key] else { return fallback }
    return intValue(value, default: fallback)
}

func optInt(_ any: Any?, index: Int, default fallback: Int = 0) -> Int {
    guard let array = any as? [Any], index < array.count else { return fallback }
    return intValue(array[index], default: fallback)
}

func optInt(_ any: Any?, default fallback: Int = 0) -> Int {
    return intValue(any, default: fallback)
}

func intValue(_ any: Any?, default fallback: Int = 0) -> Int {
    guard let value = any else { return fallback }
    if let n = value as? NSNumber { return n.intValue }
    if let s = value as? String, let n = Int(s) { return n }
    return fallback
}

func optLong(_ any: Any?, key: String, default fallback: Int64 = 0) -> Int64 {
    guard let dict = any as? [String: Any], let value = dict[key] else { return fallback }
    return longValue(value, default: fallback)
}

func optLong(_ any: Any?, default fallback: Int64 = 0) -> Int64 {
    return longValue(any, default: fallback)
}

func longValue(_ any: Any?, default fallback: Int64 = 0) -> Int64 {
    guard let value = any else { return fallback }
    if let n = value as? NSNumber { return n.int64Value }
    if let s = value as? String, let n = Int64(s) { return n }
    return fallback
}

func optBool(_ any: Any?, key: String, default fallback: Bool = false) -> Bool {
    guard let dict = any as? [String: Any], let value = dict[key] else { return fallback }
    return boolValue(value, default: fallback)
}

func optBool(_ any: Any?, default fallback: Bool = false) -> Bool {
    return boolValue(any, default: fallback)
}

func boolValue(_ any: Any?, default fallback: Bool = false) -> Bool {
    guard let value = any else { return fallback }
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.boolValue }
    if let s = value as? String { return !s.isEmpty && s != "false" && s != "0" }
    return fallback
}

func optArray(_ any: Any?, key: String) -> [Any]? {
    guard let dict = any as? [String: Any], let value = dict[key] else { return nil }
    return value as? [Any]
}

func optArray(_ any: Any?) -> [Any]? {
    return any as? [Any]
}

func optObjectAny(_ any: Any?, key: String) -> Any? {
    guard let dict = any as? [String: Any] else { return nil }
    return dict[key]
}

func optDictionary(_ any: Any?, key: String) -> [String: Any]? {
    guard let dict = any as? [String: Any], let value = dict[key] else { return nil }
    return value as? [String: Any]
}

func arrayLength(_ any: Any?) -> Int {
    return (any as? [Any])?.count ?? 0
}

// MARK: - building (mutable dictionaries / arrays)

func jsonObject() -> [String: Any] { return [:] }

func arrayString(_ items: [String]) -> [String] { return items }
