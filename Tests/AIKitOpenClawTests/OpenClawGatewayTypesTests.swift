import XCTest
@testable import AIKitOpenClaw
import AIKitProviders

final class OpenClawGatewayTypesTests: XCTestCase {
  func testAgentsListParsesIdentityFields() {
    let payload: JSONValue = .object([
      "defaultId": .string("main"),
      "agents": .array([
        .object([
          "id": .string("main"),
          "name": .string("Main Agent"),
          "identity": .object([
            "name": .string("Claw"),
            "emoji": .string("🦞"),
            "avatar": .string("avatars/openclaw.png"),
            "avatarUrl": .string("https://example.com/openclaw.png"),
          ]),
        ]),
      ]),
    ])

    let parsed = OpenClawAgentsList(from: payload)
    XCTAssertEqual(parsed?.defaultId, "main")
    XCTAssertEqual(parsed?.agents.count, 1)
    XCTAssertEqual(parsed?.agents.first?.id, "main")
    XCTAssertEqual(parsed?.agents.first?.identity?.emoji, "🦞")
    XCTAssertEqual(parsed?.agents.first?.identity?.avatarUrl, "https://example.com/openclaw.png")
  }

  func testAgentFileParsesNestedContentFromAgentsFilesGet() {
    let payload: JSONValue = .object([
      "agentId": .string("main"),
      "workspace": .string("/tmp/ws"),
      "file": .object([
        "name": .string("SOUL.md"),
        "missing": .bool(false),
        "content": .string("# SOUL\n"),
      ]),
    ])

    let parsed = OpenClawAgentFile(from: payload)
    XCTAssertEqual(parsed?.content, "# SOUL\n")
  }

  func testAgentFileParsesMissingFlagAsEmptyContent() {
    let payload: JSONValue = .object([
      "file": .object([
        "name": .string("SOUL.md"),
        "missing": .bool(true),
      ]),
    ])

    let parsed = OpenClawAgentFile(from: payload)
    XCTAssertEqual(parsed?.content, "")
  }

  func testSkillsStatusParsesEligibilityAndRequirements() {
    let payload: JSONValue = .object([
      "skills": .array([
        .object([
          "name": .string("calendar"),
          "description": .string("Calendar tools"),
          "source": .string("openclaw-workspace"),
          "emoji": .string("📅"),
          "eligible": .bool(true),
          "disabled": .bool(false),
          "blockedByAllowlist": .bool(false),
          "always": .bool(false),
          "requirements": .object([
            "bins": .array([.string("jq")]),
            "env": .array([.string("GOOGLE_API_KEY")]),
            "config": .array([.string("calendar.enabled")]),
            "os": .array([.string("darwin")]),
          ]),
        ]),
      ]),
    ])

    let parsed = OpenClawSkillsStatus(from: payload)
    XCTAssertEqual(parsed?.skills.count, 1)
    XCTAssertEqual(parsed?.skills.first?.name, "calendar")
    XCTAssertEqual(parsed?.skills.first?.source, "openclaw-workspace")
    XCTAssertEqual(parsed?.skills.first?.eligible, true)
    XCTAssertEqual(parsed?.skills.first?.requirements?.bins, ["jq"])
    XCTAssertEqual(parsed?.skills.first?.requirements?.env, ["GOOGLE_API_KEY"])
  }
}
