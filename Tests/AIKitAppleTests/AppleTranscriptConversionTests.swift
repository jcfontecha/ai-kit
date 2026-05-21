import XCTest
import FoundationModels
import AIKitProviders
@testable import AIKitApple

final class AppleTranscriptConversionTests: XCTestCase {
  func testToolCallsAreConvertedToProviderToolCalls() {
    let arguments = appleGeneratedContent(
      from: .object([
        "city": .string("Madrid"),
      ])
    )

    let entry: Transcript.Entry = .toolCalls(
      .init(
        id: "calls-1",
        [Transcript.ToolCall(id: "call-1", toolName: "weather", arguments: arguments)]
      )
    )

    let toolCalls = appleToolCalls(from: [entry])
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolCalls[0].toolCallID, "call-1")
    XCTAssertEqual(toolCalls[0].toolName, "weather")
    XCTAssertEqual(toolCalls[0].input, .object(["city": .string("Madrid")]))
  }

  func testResponseTextIncludesTextAndStructuredSegments() {
    let structured = appleGeneratedContent(
      from: .object([
        "name": .string("Person"),
      ])
    )
    let response: Transcript.Entry = .response(
      .init(
        id: "response-1",
        assetIDs: [],
        segments: [
          .text(.init(id: "t1", content: "Hello ")),
          .structure(.init(id: "s1", source: "Person", content: structured)),
        ]
      )
    )

    let text = appleResponseText(from: [response])
    XCTAssertTrue(text.contains("Hello"))
    XCTAssertTrue(text.contains("\"name\""))
    XCTAssertEqual(appleResponseID(from: [response]), "response-1")
  }
}
