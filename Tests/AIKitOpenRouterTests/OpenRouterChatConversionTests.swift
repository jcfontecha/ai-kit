import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterChatConversionTests: XCTestCase {
  func testConvertImageData() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .user,
        content: [
          .text(.init(text: "Hello")),
          .file(.init(data: .data(Data([0, 1, 2, 3])), mediaType: "image/png"))
        ]
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .parts([
          .text("Hello", cacheControl: nil),
          .imageURL("data:image/png;base64,AAECAw==", cacheControl: nil),
        ]),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testConvertImageURL() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .user,
        content: [
          .text(.init(text: "Hello")),
          .file(.init(data: .url(URL(string: "https://example.com/image.png")!), mediaType: "image/png"))
        ]
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .parts([
          .text("Hello", cacheControl: nil),
          .imageURL("https://example.com/image.png", cacheControl: nil),
        ]),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testConvertImageBase64() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .user,
        content: [
          .text(.init(text: "Hello")),
          .file(.init(data: .base64("data:image/png;base64,AAECAw=="), mediaType: "image/png"))
        ]
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .parts([
          .text("Hello", cacheControl: nil),
          .imageURL("data:image/png;base64,AAECAw==", cacheControl: nil),
        ]),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testConvertSingleTextMessageToString() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(role: .user, content: [.text(.init(text: "Hello"))])
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .string("Hello"),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testConvertAudioData() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .user,
        content: [
          .file(.init(data: .data(Data([0, 1, 2, 3])), mediaType: "audio/mpeg"))
        ]
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .parts([
          .inputAudio(data: "AAECAw==", format: .mp3, cacheControl: nil),
        ]),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testConvertAudioDataURL() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .user,
        content: [
          .file(.init(data: .base64("data:audio/mpeg;base64,AAECAw=="), mediaType: "audio/mpeg"))
        ]
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .parts([
          .inputAudio(data: "AAECAw==", format: .mp3, cacheControl: nil),
        ]),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testAudioURLThrows() {
    XCTAssertThrowsError(
      try convertToOpenRouterChatMessages([
        .init(
          role: .user,
          content: [
            .file(.init(data: .url(URL(string: "https://example.com/audio.mp3")!), mediaType: "audio/mpeg"))
          ]
        )
      ])
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("Audio files cannot be provided as URLs"))
    }
  }

  func testUnsupportedAudioFormatThrows() {
    XCTAssertThrowsError(
      try convertToOpenRouterChatMessages([
        .init(
          role: .user,
          content: [
            .file(.init(data: .data(Data([0, 1, 2, 3])), mediaType: "audio/webm"))
          ]
        )
      ])
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("Unsupported audio format"))
    }
  }

  func testCacheControlFromSystemMessage() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .system,
        content: [.text(.init(text: "System prompt"))],
        providerOptions: cacheControlOptions(provider: "anthropic")
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "system",
        content: .string("System prompt"),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: .init(type: "ephemeral")
      )
    ])
  }

  func testCacheControlFromUserMessageSingleText() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .user,
        content: [.text(.init(text: "Hello"))],
        providerOptions: cacheControlOptions(provider: "anthropic")
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .parts([
          .text("Hello", cacheControl: .init(type: "ephemeral")),
        ]),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testCacheControlFromContentPart() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .user,
        content: [
          .text(.init(text: "Hello", providerOptions: cacheControlOptions(provider: "anthropic")))
        ]
      )
    ])

    XCTAssertEqual(result, [
      OpenRouterChatMessage(
        role: "user",
        content: .parts([
          .text("Hello", cacheControl: .init(type: "ephemeral")),
        ]),
        toolCalls: nil,
        toolCallID: nil,
        reasoning: nil,
        reasoningDetails: nil,
        annotations: nil,
        cacheControl: nil
      )
    ])
  }

  func testReasoningDetailsAccumulation() throws {
    let result = try convertToOpenRouterChatMessages([
      .init(
        role: .assistant,
        content: [
          .reasoning(.init(
            text: "First reasoning chunk",
            providerOptions: openRouterReasoningOptions([
              .text(.init(type: .text, text: "First reasoning chunk", signature: nil, id: nil, format: nil, index: nil))
            ])
          )),
          .reasoning(.init(
            text: "Second reasoning chunk",
            providerOptions: openRouterReasoningOptions([
              .text(.init(type: .text, text: "Second reasoning chunk", signature: nil, id: nil, format: nil, index: nil))
            ])
          )),
          .text(.init(text: "Final response"))
        ],
        providerOptions: openRouterReasoningOptions([
          .text(.init(type: .text, text: "First reasoning chunk", signature: nil, id: nil, format: nil, index: nil)),
          .text(.init(type: .text, text: "Second reasoning chunk", signature: nil, id: nil, format: nil, index: nil))
        ])
      )
    ])

    XCTAssertEqual(result.first?.reasoning, "First reasoning chunkSecond reasoning chunk")
    XCTAssertEqual(result.first?.content, .string("Final response"))
    XCTAssertEqual(result.first?.reasoningDetails?.count, 2)
  }

  private func cacheControlOptions(provider: String) -> ProviderOptions {
    [provider: ["cacheControl": .object(["type": .string("ephemeral")])]]
  }

  private func openRouterReasoningOptions(_ details: [ReasoningDetailUnion]) -> ProviderOptions {
    ["openrouter": ["reasoning_details": OpenRouterJSON.encodeToJSONValue(details) ?? .array([])]]
  }
}
