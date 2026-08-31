import Foundation

/// Persists the session store JSON to the app's Documents directory, mirroring the
/// Android `SessionStorage` file (`study_suit_sessions_v1.json`) so payloads remain
/// interchangeable across platforms.
final class SessionStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.fileURL = dir.appendingPathComponent("study_suit_sessions_v1.json")
        }
    }

    func exportPayloadJson(_ payload: PersistedSessions) -> String {
        return JSON.string(buildRootJson(payload))
    }

    func save(_ payload: PersistedSessions) -> Result<Void, Error> {
        do {
            let root = buildRootJson(payload)
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func load() -> PersistedSessions? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            switch parsePersistedSessionsJson(raw) {
            case .success(let payload): return payload
            case .failure: return nil
            }
        } catch {
            return nil
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
