import XCTest
@testable import ArtIflow

final class SessionRegistryTests: XCTestCase {
    func testPutAndTouchMovesSessionToFront() {
        let registry = SessionRegistry()
        let sessionA = makeStoredSession(id: "a", updatedAt: 10)
        let sessionB = makeStoredSession(id: "b", updatedAt: 20)
        registry.put(sessionA, moveToFront: false)
        registry.put(sessionB, moveToFront: false)
        var touched = sessionA
        touched.updatedAt = 30
        registry.put(touched, moveToFront: true)

        let ordered = registry.orderedSessions()
        XCTAssertEqual(ordered.map { $0.id }, ["a", "b"])
        XCTAssertEqual(ordered.first?.updatedAt, 30)
    }

    func testReplaceAllResetsRegistryContent() {
        let registry = SessionRegistry()
        registry.put(makeStoredSession(id: "old", updatedAt: 1), moveToFront: false)
        registry.replaceAll([makeStoredSession(id: "x", updatedAt: 11), makeStoredSession(id: "y", updatedAt: 12)])
        XCTAssertFalse(registry.contains("old"))
        XCTAssertEqual(registry.orderedSessions().map { $0.id }, ["x", "y"])
    }

    func testRemoveAndClearUpdateEmptyState() {
        let registry = SessionRegistry()
        registry.put(makeStoredSession(id: "a", updatedAt: 1), moveToFront: false)
        registry.put(makeStoredSession(id: "b", updatedAt: 2), moveToFront: false)
        registry.remove("a")
        XCTAssertFalse(registry.contains("a"))
        XCTAssertEqual(registry.firstIdOrNull(), "b")
        registry.clear()
        XCTAssertTrue(registry.isEmpty())
        XCTAssertNil(registry.firstIdOrNull())
    }

    func testCreatedAtOfReturnsValueForExistingSession() {
        let registry = SessionRegistry()
        registry.put(makeStoredSession(id: "a", updatedAt: 100), moveToFront: false)
        XCTAssertEqual(registry.createdAtOf("a"), 100)
        XCTAssertNil(registry.createdAtOf("missing"))
    }
}
