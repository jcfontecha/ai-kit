import XCTest
import AIKitProviders
@testable import AIKitApple

final class ApplePromptAndOptionsTests: XCTestCase {
  func testPreparePromptSeparatesInstructionsAndConversation() throws {
    let messages: [ModelMessage] = [
      .system("You are concise."),
      .user("Hello"),
      .assistant("Hi!"),
    ]

    let prepared = try applePreparePrompt(
      from: messages,
      toolChoiceInstruction: "You must call at least one tool."
    )

    XCTAssertEqual(prepared.instructions, "You are concise.")
    XCTAssertTrue(prepared.prompt.contains("User:\nHello"))
    XCTAssertTrue(prepared.prompt.contains("Assistant:\nHi!"))
    XCTAssertTrue(prepared.prompt.contains("You must call at least one tool."))
  }

  func testPreparePromptSingleUserMessageKeepsRawPrompt() throws {
    let prepared = try applePreparePrompt(
      from: [.user("Raw prompt")],
      toolChoiceInstruction: nil
    )

    XCTAssertNil(prepared.instructions)
    XCTAssertEqual(prepared.prompt, "Raw prompt")
  }

  func testPreparePromptRejectsImageParts() {
    let message = ModelMessage(
      role: .user,
      content: [
        .image(.init(data: .data(Data()))),
      ]
    )

    XCTAssertThrowsError(
      try applePreparePrompt(from: [message], toolChoiceInstruction: nil)
    ) { error in
      guard case let AIKitError.invalidConfiguration(message) = error else {
        XCTFail("Expected invalid configuration error")
        return
      }
      XCTAssertTrue(message.contains("text-only"))
    }
  }

  func testBuildGenerationOptionsReportsUnsupportedSettings() {
    let result = buildGenerationOptions(
      from: .init(
        topP: 0.5,
        topK: 20,
        presencePenalty: 1.0,
        frequencyPenalty: 1.0,
        stopSequences: ["END"]
      )
    )

    XCTAssertNotNil(result.options.sampling)
    XCTAssertEqual(result.warnings.count, 4)
  }

  func testSelectToolsHonorsSpecificToolChoice() {
    let schema = JSONSchema.object(
      properties: ["value": .string()],
      required: ["value"],
      additionalProperties: false
    )
    let tools: [ToolDefinition] = [
      .init(name: "weather", inputSchema: schema),
      .init(name: "calendar", inputSchema: schema),
    ]

    let selected = selectTools(
      request: .init(
        messages: [.user("test")],
        tools: tools,
        toolChoice: .tool(name: "calendar")
      )
    )

    XCTAssertEqual(selected.tools.map(\.name), ["calendar"])
    XCTAssertTrue(selected.warnings.isEmpty)
  }
}
