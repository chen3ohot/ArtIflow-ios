import XCTest
@testable import ArtIflow

final class FlowStudySyncClientTests: XCTestCase {
    func testPairDeviceNonJsonErrorBodyKeepsServerTextInFailureMessage() async {
        let client = FlowStudySyncClient(transport: StaticHTTPTransport(code: 502, body: "<html>bad gateway</html>", contentType: "text/html; charset=utf-8"))
        let result = await client.pairDevice(serverUrl: "https://flow.example.com", pairCode: "PAIR-001", deviceId: "device-a")
        switch result {
        case .success: XCTFail("expected failure")
        case .failure(let error):
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("配对失败 (502)"))
            XCTAssertTrue(message.contains("bad gateway"))
        }
    }

    func testPushSessionsSuccessResponseParsesCounters() async {
        let client = FlowStudySyncClient(transport: StaticHTTPTransport(code: 200, body: #"{"inserted_sessions":2,"updated_sessions":1,"skipped_sessions":3,"import_batch_id":"batch-42"}"#))
        let result = await client.pushSessions(
            serverUrl: "https://flow.example.com",
            deviceToken: "token-a",
            deviceId: "device-a",
            payloadJson: #"{"activeSessionId":"s1","settings":{},"sessions":[]}"#
        )
        switch result {
        case .success(let payload):
            XCTAssertEqual(payload.insertedSessions, 2)
            XCTAssertEqual(payload.updatedSessions, 1)
            XCTAssertEqual(payload.skippedSessions, 3)
            XCTAssertEqual(payload.importBatchId, "batch-42")
        case .failure(let error): XCTFail("expected success: \(error)")
        }
    }
}
