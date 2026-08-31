import XCTest
@testable import ArtIflow

final class SessionStorageParsingTests: XCTestCase {
    func testEmptySessionsKeepsSettingsPayload() {
        let raw = """
        {
          "version": 1,
          "activeSessionId": "",
          "settings": {
            "arkApiKey": "ark-key",
            "flowStudyServerUrl": "https://flow.example.com",
            "flowStudyDeviceId": "device-1",
            "flowStudyDeviceToken": "token-1",
            "customModelBaseUrl": "https://api.openai.com/v1",
            "customModelApiKey": "custom-key",
            "customModelName": "gpt-4o-mini"
          },
          "sessions": []
        }
        """
        let result = parsePersistedSessionsJson(raw)
        switch result {
        case .success(let parsed):
            XCTAssertEqual(parsed.activeSessionId, "")
            XCTAssertTrue(parsed.sessions.isEmpty)
            XCTAssertEqual(parsed.settings.arkApiKey, "ark-key")
            XCTAssertEqual(parsed.settings.flowStudyServerUrl, "https://flow.example.com")
            XCTAssertEqual(parsed.settings.flowStudyDeviceId, "device-1")
            XCTAssertEqual(parsed.settings.flowStudyDeviceToken, "token-1")
            XCTAssertEqual(parsed.settings.customModelBaseUrl, "https://api.openai.com/v1")
            XCTAssertEqual(parsed.settings.customModelApiKey, "custom-key")
            XCTAssertEqual(parsed.settings.customModelName, "gpt-4o-mini")
        case .failure:
            XCTFail("expected success")
        }
    }

    func testRestoresCustomModelPresets() {
        let raw = """
        {
          "version": 1,
          "activeSessionId": "",
          "settings": {
            "customModelPresets": [
              {"id":"preset-1","name":"OpenAI 日常","baseUrl":"https://api.openai.com/v1","apiKey":"secret-key","modelName":"gpt-4o-mini"}
            ]
          },
          "sessions": []
        }
        """
        let parsed = try! parsePersistedSessionsJson(raw).get()
        XCTAssertEqual(parsed.settings.customModelPresets.count, 1)
        XCTAssertEqual(parsed.settings.customModelPresets.first?.name, "OpenAI 日常")
        XCTAssertEqual(parsed.settings.customModelPresets.first?.modelName, "gpt-4o-mini")
    }

    func testLegacyModelNormalizesToDefault() {
        let raw = """
        {
          "version": 1,
          "activeSessionId": "session-1",
          "settings": {"arkModel": "doubao-seed-1-8-251228"},
          "sessions": []
        }
        """
        let parsed = try! parsePersistedSessionsJson(raw).get()
        XCTAssertNotEqual("doubao-seed-1-8-251228", parsed.settings.arkModel)
        XCTAssertEqual(RuntimeSettings.defaults().arkModel, parsed.settings.arkModel)
    }

    func testInvalidPayloadReturnsFailure() {
        let result = parsePersistedSessionsJson("{not-valid-json")
        switch result {
        case .success: XCTFail("expected failure")
        case .failure: break
        }
    }

    func testBuildUiStateFromSessionSanitizesLegacyArtifacts() {
        let session = StoredSession(
            id: "session-1", title: "主界面", createdAt: 1, updatedAt: 2,
            messages: [], histories: [:], profile: ProfileState(level: "高二"),
            input: "", coachInput: "", activePage: .chat, quickFollowupSpanId: nil, quickFollowupDetailId: nil,
            coachMessages: [], coachDigest: nil, dailyTraining: DailyTrainingState(),
            savedQuestions: [
                SavedQuestion(id: "saved-1", sourceMessageId: "msg-1", question: "函数题", answer: "看导数", sourceTime: "10:00", savedAt: 3, knowledgeTags: ["方法总结", "导数"])
            ],
            knowledgePoints: ["不会": 5, "电流": 2],
            ankiCards: [
                AnkiCard(id: "card-1", front: "q", back: "a", tags: ["方法总结", "电流"], source: "src", createdAt: 4, deckName: "方法总结")
            ]
        )
        let rebuilt = buildUiStateFromSession(session: session, ankiCards: session.ankiCards, settings: RuntimeSettings.defaults(), toastMessage: nil)
        XCTAssertEqual(rebuilt.savedQuestions.first?.knowledgeTags, ["函数与图像", "导数与应用"])
        XCTAssertEqual(rebuilt.knowledgePoints, ["电磁学": 2])
        XCTAssertEqual(rebuilt.ankiCards.first?.tags, ["电磁学"])
        XCTAssertEqual(rebuilt.ankiCards.first?.deckName, "电磁学卡组")
    }

    func testRestoresSavedQuestionsArchive() {
        let raw = """
        {
          "version": 1,
          "activeSessionId": "session-1",
          "settings": {},
          "sessions": [
            {
              "id": "session-1", "title": "主界面", "createdAt": 1, "updatedAt": 2,
              "input": "", "activePage": "ARCHIVE", "profile": {"level": "高二"},
              "messages": [],
              "savedQuestions": [
                {"id":"saved-1","sourceMessageId":"msg-2","question":"这题怎么做","answer":"先设未知数，再列方程。","sourceTime":"10:01","savedAt":99,"followupCount":2,"knowledgeTags":["方程","设元"]},
                {"id":"saved-2","sourceMessageId":"msg-3","question":"   ","answer":"这条应该被过滤","sourceTime":"10:02","savedAt":100,"followupCount":0,"knowledgeTags":[]}
              ],
              "knowledgePoints": {}, "ankiCards": [], "histories": {}
            }
          ]
        }
        """
        let parsed = try! parsePersistedSessionsJson(raw).get()
        let session = parsed.sessions.first!
        let saved = session.savedQuestions
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id, "saved-1")
        XCTAssertEqual(saved.first?.sourceMessageId, "msg-2")
        XCTAssertEqual(saved.first?.question, "这题怎么做")
        XCTAssertEqual(saved.first?.answer, "先设未知数，再列方程。")
        XCTAssertEqual(saved.first?.sourceTime, "10:01")
        XCTAssertEqual(saved.first?.savedAt, 99)
        XCTAssertEqual(saved.first?.followupCount, 2)
        XCTAssertEqual(saved.first?.knowledgeTags, ["方程", "设元"])
        XCTAssertEqual(session.activePage, .archive)
    }

    func testWithoutMainSpanBuildsLegacyQuestionScopeCard() {
        let raw = """
        {
          "version": 1,
          "activeSessionId": "session-1",
          "settings": {},
          "sessions": [
            {
              "id": "session-1", "title": "主界面", "createdAt": 1, "updatedAt": 2,
              "input": "", "activePage": "CHAT", "profile": {"level": "高二"},
              "messages": [
                {"type":"assistant","id":"msg-2","time":"10:01","spans":[
                  {"id":"span-1","content":"第一段","sourceQuestion":"这题怎么做"},
                  {"id":"span-2","content":"第二段","sourceQuestion":"这题怎么做"}
                ]}
              ],
              "knowledgePoints": {}, "ankiCards": [], "histories": {}
            }
          ]
        }
        """
        let parsed = try! parsePersistedSessionsJson(raw).get()
        guard case .assistant(_, _, _, let mainSpan, _) = parsed.sessions.first!.messages.first! else {
            return XCTFail("expected assistant")
        }
        XCTAssertNotNil(mainSpan)
        XCTAssertEqual(mainSpan?.id, "assistant-main-msg-2")
        XCTAssertTrue(mainSpan?.content.contains("第一段") ?? false)
        XCTAssertTrue(mainSpan?.content.contains("第二段") ?? false)
    }
}
