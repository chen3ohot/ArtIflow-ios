import Foundation
@testable import ArtIflow

final class StaticHTTPTransport: HTTPTransport {
    private let data: Data
    private let response: HTTPURLResponse

    init(code: Int, body: String, contentType: String = "application/json; charset=utf-8") {
        self.data = body.data(using: .utf8) ?? Data()
        let url = URL(string: "https://test.example.com")!
        self.response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": contentType
        ])!
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        return (data, response)
    }
}

func makeStoredSession(id: String, updatedAt: Int64) -> StoredSession {
    return StoredSession(
        id: id,
        title: "session-\(id)",
        createdAt: updatedAt,
        updatedAt: updatedAt,
        messages: [],
        histories: [:],
        profile: ProfileState(level: "L"),
        input: "",
        coachInput: "",
        activePage: .chat,
        quickFollowupSpanId: nil,
        quickFollowupDetailId: nil,
        coachMessages: [],
        coachDigest: nil,
        dailyTraining: DailyTrainingState(),
        savedQuestions: [],
        knowledgePoints: [:],
        ankiCards: []
    )
}
