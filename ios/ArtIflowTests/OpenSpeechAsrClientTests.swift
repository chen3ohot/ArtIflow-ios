import XCTest
@testable import ArtIflow

final class OpenSpeechAsrClientTests: XCTestCase {
    func testPrefersResultText() {
        let transcript = parseOpenSpeechTranscript(#"{"result":{"text":"这是最终识别文本"}}"#)
        XCTAssertEqual(transcript, "这是最终识别文本")
    }

    func testFallsBackToUtteranceList() {
        let transcript = parseOpenSpeechTranscript(#"{"result":{"utterances":[{"text":"第一句"},{"text":"第二句"}]}}"#)
        XCTAssertEqual(transcript, "第一句\n第二句")
    }

    func testInvalidJsonReturnsBlank() {
        XCTAssertEqual(parseOpenSpeechTranscript("not-json"), "")
    }
}
