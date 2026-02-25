import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders

private extension JSONValue {
  subscript(_ key: String) -> JSONValue? {
    guard case let .object(obj) = self else { return nil }
    return obj[key]
  }
}

final class ConvertToModelMessagesTests: XCTestCase {
  private static func toolOutputText(_ value: String) -> JSONValue {
    .object(["type": .string("text"), "value": .string(value)])
  }

  private func toolOutputJSON(_ value: JSONValue) -> JSONValue {
    .object(["type": .string("json"), "value": value])
  }

  private func toolOutputErrorText(_ value: String) -> JSONValue {
    .object(["type": .string("error-text"), "value": .string(value)])
  }

  private func toolOutputErrorJSON(_ value: String) -> JSONValue {
    .object(["type": .string("error-json"), "value": .string(value)])
  }

  private func object(_ value: JSONValue?) -> [String: JSONValue]? {
    guard case let .object(obj)? = value else { return nil }
    return obj
  }

  private static func stringField(_ key: String, in object: JSONValue) -> String? {
    guard case let .object(obj) = object else { return nil }
    guard case let .string(value)? = obj[key] else { return nil }
    return value
  }

  func testSystemMessage_simple() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "s1",
        role: .system,
        parts: [
          .text(.init(id: "t1", text: "System message", state: .done)),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .system, content: [.text(.init(text: "System message"))]),
    ])
  }

  func testSystemMessage_providerMetadata() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "s1",
        role: .system,
        parts: [
          .text(.init(
            id: "t1",
            text: "System message with metadata",
            state: .done,
            providerMetadata: ["testProvider": .object(["systemSignature": .string("abc123")])]
          )),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].role, .system)
    XCTAssertEqual(result[0].providerOptions?["testProvider"]?["systemSignature"], .string("abc123"))

    guard case let .text(textPart) = result[0].content.first else { return XCTFail("expected text part") }
    XCTAssertEqual(textPart.text, "System message with metadata")
  }

  func testSystemMessage_concatenatesTextPartsAndMergesProviderMetadataIntoProviderOptions() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "s1",
        role: .system,
        parts: [
          .text(.init(id: "t1", text: "Part 1", state: .done, providerMetadata: ["p1": .object(["k1": .string("v1")])])),
          .text(.init(id: "t2", text: " Part 2", state: .done, providerMetadata: ["p2": .object(["k2": .string("v2")])])),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].role, .system)
    XCTAssertEqual(result[0].providerOptions?["p1"]?["k1"], .string("v1"))
    XCTAssertEqual(result[0].providerOptions?["p2"]?["k2"], .string("v2"))

    guard case let .text(textPart) = result[0].content.first else { return XCTFail("expected text part") }
    XCTAssertEqual(textPart.text, "Part 1 Part 2")
  }

  func testSystemMessage_anthropicCacheControlMetadata() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "system",
        role: .system,
        parts: [
          .text(.init(
            id: "t1",
            text: "You are a helpful assistant.",
            state: .done,
            providerMetadata: ["anthropic": .object(["cacheControl": .object(["type": .string("ephemeral")])])]
          )),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].role, .system)
    XCTAssertEqual(result[0].providerOptions?["anthropic"]?["cacheControl"]?["type"], .string("ephemeral"))
  }

  func testUserMessage_simple() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .text(.init(id: "t1", text: "Hello, AI!", state: .done)),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .user, content: [.text(.init(text: "Hello, AI!"))]),
    ])
  }

  func testUserMessage_dataParts_areSkippedByDefault_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in user messages' → 'should skip data parts when no converter provided')`.
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .text(.init(id: "t1", text: "Hello", state: .done)),
          .data(.init(type: "data-url", data: .object(["url": .string("https://example.com")]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .user, content: [.text(.init(text: "Hello"))]),
    ])
  }

  func testUserMessage_dataParts_convertToTextWhenConverterProvided_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in user messages' → 'should convert data parts to text when converter provided')`.
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .data(.init(type: "data-url", data: .object([
            "url": .string("https://example.com"),
            "content": .string("Article text"),
          ]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        guard part.type == "data-url" else { return nil }
        guard let url = Self.stringField("url", in: part.data) else { return nil }
        guard let content = Self.stringField("content", in: part.data) else { return nil }
        return .text(.init(text: "\n\n[\(url)]\n\(content)"))
      })
    )

    XCTAssertEqual(result, [
      .init(role: .user, content: [.text(.init(text: "\n\n[https://example.com]\nArticle text"))]),
    ])
  }

  func testUserMessage_dataParts_selectivelyConverted_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in user messages' → 'should selectively convert data parts')`.
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .data(.init(type: "data-url", data: .object(["url": .string("https://example.com")]))),
          .data(.init(type: "data-ui-state", data: .object(["enabled": .bool(true)]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        if part.type == "data-url", let url = Self.stringField("url", in: part.data) {
          return .text(.init(text: url))
        }
        return nil
      })
    )

    XCTAssertEqual(result, [
      .init(role: .user, content: [.text(.init(text: "https://example.com"))]),
    ])
  }

  func testUserMessage_dataParts_convertToFileParts_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in user messages' → 'should convert data parts to file parts')`.
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .text(.init(id: "t1", text: "Check this file", state: .done)),
          .data(.init(type: "data-attachment", data: .object([
            "mediaType": .string("application/pdf"),
            "filename": .string("document.pdf"),
            "data": .string("base64data"),
          ]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        guard part.type == "data-attachment" else { return nil }
        guard let mediaType = Self.stringField("mediaType", in: part.data) else { return nil }
        guard let filename = Self.stringField("filename", in: part.data) else { return nil }
        guard let data = Self.stringField("data", in: part.data) else { return nil }
        return .file(.init(data: .base64(data), filename: filename, mediaType: mediaType))
      })
    )

    XCTAssertEqual(result, [
      .init(role: .user, content: [
        .text(.init(text: "Check this file")),
        .file(.init(data: .base64("base64data"), filename: "document.pdf", mediaType: "application/pdf")),
      ]),
    ])
  }

  func testUserMessage_dataParts_multipleTypes_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in user messages' → 'should handle multiple data parts of different types')`.
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .text(.init(id: "t1", text: "Review these:", state: .done)),
          .data(.init(type: "data-url", data: .object([
            "url": .string("https://example.com"),
            "title": .string("Example"),
          ]))),
          .data(.init(type: "data-code", data: .object([
            "code": .string("console.log(\"test\")"),
            "language": .string("javascript"),
          ]))),
          .data(.init(type: "data-note", data: .object(["text": .string("Internal note")]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        switch part.type {
        case "data-url":
          guard let url = Self.stringField("url", in: part.data) else { return nil }
          guard let title = Self.stringField("title", in: part.data) else { return nil }
          return .text(.init(text: "[\(title)](\(url))"))
        case "data-code":
          guard let code = Self.stringField("code", in: part.data) else { return nil }
          guard let language = Self.stringField("language", in: part.data) else { return nil }
          return .text(.init(text: "```\(language)\n\(code)\n```"))
        default:
          return nil
        }
      })
    )

    XCTAssertEqual(result, [
      .init(role: .user, content: [
        .text(.init(text: "Review these:")),
        .text(.init(text: "[Example](https://example.com)")),
        .text(.init(text: "```javascript\nconsole.log(\"test\")\n```")),
      ]),
    ])
  }

  func testUserMessage_dataParts_converterDoesNotAffectMessagesWithoutData_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in user messages' → 'should work with messages that have no data parts')`.
    let url = URL(string: "https://example.com/image.png")!
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .text(.init(id: "t1", text: "Hello", state: .done)),
          .file(.init(data: .url(url), filename: nil, mediaType: "image/png")),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { _ in .text(.init(text: "converted")) })
    )

    XCTAssertEqual(result, [
      .init(role: .user, content: [
        .text(.init(text: "Hello")),
        .file(.init(data: .url(url), filename: nil, mediaType: "image/png")),
      ]),
    ])
  }

  func testUserMessage_dataParts_preserveOrder_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in user messages' → 'should preserve order of parts including converted data parts')`.
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .text(.init(id: "t1", text: "First", state: .done)),
          .data(.init(type: "data-tag", data: .object(["value": .string("tag1")]))),
          .text(.init(id: "t2", text: "Second", state: .done)),
          .data(.init(type: "data-tag", data: .object(["value": .string("tag2")]))),
          .text(.init(id: "t3", text: "Third", state: .done)),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        guard part.type == "data-tag" else { return nil }
        guard let value = Self.stringField("value", in: part.data) else { return nil }
        return .text(.init(text: "[\(value)]"))
      })
    )

    XCTAssertEqual(result, [
      .init(role: .user, content: [
        .text(.init(text: "First")),
        .text(.init(text: "[tag1]")),
        .text(.init(text: "Second")),
        .text(.init(text: "[tag2]")),
        .text(.init(text: "Third")),
      ]),
    ])
  }

  func testAssistantMessage_dataParts_convertToTextWhenConverterProvided_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in assistant messages' → 'should convert data parts to text when converter provided')`.
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .data(.init(type: "data-url", data: .object([
            "url": .string("https://example.com"),
            "content": .string("Article text"),
          ]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        guard part.type == "data-url" else { return nil }
        guard let url = Self.stringField("url", in: part.data) else { return nil }
        guard let content = Self.stringField("content", in: part.data) else { return nil }
        return .text(.init(text: "\n\n[\(url)]\n\(content)"))
      })
    )

    XCTAssertEqual(result, [
      .init(role: .assistant, content: [.text(.init(text: "\n\n[https://example.com]\nArticle text"))]),
    ])
  }

  func testAssistantMessage_dataParts_areSkippedByDefault_whenConverterMissing_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in assistant messages' → 'should skip data parts when no converter provided')`.
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .text(.init(id: "t1", text: "Hello", state: .done)),
          .data(.init(type: "data-url", data: .object(["url": .string("https://example.com")]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .assistant, content: [.text(.init(text: "Hello"))]),
    ])
  }

  func testAssistantMessage_dataParts_selectivelyConverted_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in assistant messages' → 'should selectively convert data parts')`.
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .data(.init(type: "data-url", data: .object(["url": .string("https://example.com")]))),
          .data(.init(type: "data-ui-state", data: .object(["enabled": .bool(true)]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        if part.type == "data-url", let url = Self.stringField("url", in: part.data) {
          return .text(.init(text: url))
        }
        return nil
      })
    )

    XCTAssertEqual(result, [
      .init(role: .assistant, content: [.text(.init(text: "https://example.com"))]),
    ])
  }

  func testAssistantMessage_dataParts_convertToFileParts_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in assistant messages' → 'should convert data parts to file parts')`.
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .text(.init(id: "t1", text: "Check this file", state: .done)),
          .data(.init(type: "data-attachment", data: .object([
            "mediaType": .string("application/pdf"),
            "filename": .string("document.pdf"),
            "data": .string("base64data"),
          ]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        guard part.type == "data-attachment" else { return nil }
        guard let mediaType = Self.stringField("mediaType", in: part.data) else { return nil }
        guard let filename = Self.stringField("filename", in: part.data) else { return nil }
        guard let data = Self.stringField("data", in: part.data) else { return nil }
        return .file(.init(data: .base64(data), filename: filename, mediaType: mediaType))
      })
    )

    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .text(.init(text: "Check this file")),
        .file(.init(data: .base64("base64data"), filename: "document.pdf", mediaType: "application/pdf")),
      ]),
    ])
  }

  func testAssistantMessage_dataParts_multipleTypes_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in assistant messages' → 'should handle multiple data parts of different types')`.
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .text(.init(id: "t1", text: "Review these:", state: .done)),
          .data(.init(type: "data-url", data: .object([
            "url": .string("https://example.com"),
            "title": .string("Example"),
          ]))),
          .data(.init(type: "data-code", data: .object([
            "code": .string("console.log(\"test\")"),
            "language": .string("javascript"),
          ]))),
          .data(.init(type: "data-note", data: .object(["text": .string("Internal note")]))),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        switch part.type {
        case "data-url":
          guard let url = Self.stringField("url", in: part.data) else { return nil }
          guard let title = Self.stringField("title", in: part.data) else { return nil }
          return .text(.init(text: "[\(title)](\(url))"))
        case "data-code":
          guard let code = Self.stringField("code", in: part.data) else { return nil }
          guard let language = Self.stringField("language", in: part.data) else { return nil }
          return .text(.init(text: "```\(language)\n\(code)\n```"))
        default:
          return nil
        }
      })
    )

    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .text(.init(text: "Review these:")),
        .text(.init(text: "[Example](https://example.com)")),
        .text(.init(text: "```javascript\nconsole.log(\"test\")\n```")),
      ]),
    ])
  }

  func testAssistantMessage_dataParts_converterDoesNotAffectMessagesWithoutData_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in assistant messages' → 'should work with messages that have no data parts')`.
    let url = URL(string: "https://example.com/image.png")!
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .text(.init(id: "t1", text: "Hello", state: .done)),
          .file(.init(data: .url(url), filename: nil, mediaType: "image/png")),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { _ in .text(.init(text: "converted")) })
    )

    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .text(.init(text: "Hello")),
        .file(.init(data: .url(url), filename: nil, mediaType: "image/png")),
      ]),
    ])
  }

  func testAssistantMessage_dataParts_preserveOrder_matchesAISDK() async throws {
    // Mirrors `describe('data part conversion' → 'in assistant messages' → 'should preserve order of parts including converted data parts')`.
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .text(.init(id: "t1", text: "First", state: .done)),
          .data(.init(type: "data-tag", data: .object(["value": .string("tag1")]))),
          .text(.init(id: "t2", text: "Second", state: .done)),
          .data(.init(type: "data-tag", data: .object(["value": .string("tag2")]))),
          .text(.init(id: "t3", text: "Third", state: .done)),
        ]
      ),
    ]

    let result = try await convertToModelMessages(
      messages,
      options: .init(convertDataPart: { part in
        guard part.type == "data-tag" else { return nil }
        guard let value = Self.stringField("value", in: part.data) else { return nil }
        return .text(.init(text: "[\(value)]"))
      })
    )

    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .text(.init(text: "First")),
        .text(.init(text: "[tag1]")),
        .text(.init(text: "Second")),
        .text(.init(text: "[tag2]")),
        .text(.init(text: "Third")),
      ]),
    ])
  }

  func testUserMessage_providerMetadata_onText() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .text(.init(
            id: "t1",
            text: "Hello, AI!",
            state: .done,
            providerMetadata: ["testProvider": .object(["signature": .string("1234567890")])]
          )),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].role, .user)
    guard case let .text(textPart) = result[0].content.first else { return XCTFail("expected text part") }
    XCTAssertEqual(textPart.text, "Hello, AI!")
    XCTAssertEqual(textPart.providerOptions?["testProvider"]?["signature"], .string("1234567890"))
  }

  func testUserMessage_fileParts() async throws {
    let url = URL(string: "https://example.com/image.jpg")!
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .file(.init(data: .url(url), filename: nil, mediaType: "image/jpeg")),
          .text(.init(id: "t1", text: "Check this image", state: .done)),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .user, content: [
        .file(.init(data: .url(url), filename: nil, mediaType: "image/jpeg")),
        .text(.init(text: "Check this image")),
      ]),
    ])
  }

  func testUserMessage_fileParts_withProviderMetadata() async throws {
    let url = URL(string: "https://example.com/image.jpg")!
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .file(.init(
            data: .url(url),
            filename: nil,
            mediaType: "image/jpeg",
            providerMetadata: ["testProvider": .object(["signature": .string("1234567890")])]
          )),
          .text(.init(id: "t1", text: "Check this image", state: .done)),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    guard case let .file(file) = result[0].content.first else { return XCTFail("expected file part") }
    XCTAssertEqual(file.mediaType, "image/jpeg")
    XCTAssertEqual(file.data, .url(url))
    XCTAssertEqual(file.providerOptions?["testProvider"]?["signature"], .string("1234567890"))
  }

  func testUserMessage_fileParts_includesFilenameWhenProvided() async throws {
    let url = URL(string: "https://example.com/image.jpg")!
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .file(.init(data: .url(url), filename: "image.jpg", mediaType: "image/jpeg")),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .user, content: [
        .file(.init(data: .url(url), filename: "image.jpg", mediaType: "image/jpeg")),
      ]),
    ])
  }

  func testUserMessage_fileParts_doesNotIncludeFilenameWhenNotProvided() async throws {
    let url = URL(string: "https://example.com/image.jpg")!
    let messages: [ChatMessage] = [
      .init(
        id: "u1",
        role: .user,
        parts: [
          .file(.init(data: .url(url), filename: nil, mediaType: "image/jpeg")),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .user, content: [
        .file(.init(data: .url(url), filename: nil, mediaType: "image/jpeg")),
      ]),
    ])
  }

  func testAssistantMessage_splitsBlocksOnStepStart() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .text(.init(id: "t1", text: "hello", state: .done)),
          .stepStart,
          .text(.init(id: "t2", text: "world", state: .done)),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result[0].role, .assistant)
    XCTAssertEqual(result[1].role, .assistant)
  }

  func testAssistantMessage_simpleText() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .text(.init(id: "t1", text: "Hello, human!", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .assistant, content: [.text(.init(text: "Hello, human!"))]),
    ])
  }

  func testAssistantMessage_textWithProviderMetadata() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .text(.init(
          id: "t1",
          text: "Hello, human!",
          state: .done,
          providerMetadata: ["testProvider": .object(["signature": .string("1234567890")])]
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    guard case let .text(textPart) = result[0].content.first else { return XCTFail("expected text part") }
    XCTAssertEqual(textPart.text, "Hello, human!")
    XCTAssertEqual(textPart.providerOptions?["testProvider"]?["signature"], .string("1234567890"))
  }

  func testAssistantMessage_reasoning() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .reasoning(.init(
          id: "r1",
          text: "Thinking...",
          state: .done,
          providerMetadata: ["testProvider": .object(["signature": .string("1234567890")])]
        )),
        .reasoning(.init(
          id: "r2",
          text: "redacted-data",
          state: .done,
          providerMetadata: ["testProvider": .object(["isRedacted": .bool(true)])]
        )),
        .text(.init(id: "t1", text: "Hello, human!", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].role, .assistant)
    XCTAssertEqual(result[0].content.count, 3)

    guard case let .reasoning(r0) = result[0].content[0] else { return XCTFail("expected reasoning part") }
    XCTAssertEqual(r0.text, "Thinking...")
    XCTAssertEqual(r0.providerOptions?["testProvider"]?["signature"], .string("1234567890"))

    guard case let .reasoning(r1) = result[0].content[1] else { return XCTFail("expected reasoning part") }
    XCTAssertEqual(r1.text, "redacted-data")
    XCTAssertEqual(r1.providerOptions?["testProvider"]?["isRedacted"], .bool(true))
  }

  func testAssistantMessage_fileParts() async throws {
    let url = URL(string: "data:image/png;base64,dGVzdA==")!
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .file(.init(data: .url(url), filename: nil, mediaType: "image/png")),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .file(.init(data: .url(url), filename: nil, mediaType: "image/png")),
      ]),
    ])
  }

  func testAssistantMessage_fileParts_includesFilenameWhenProvided() async throws {
    let url = URL(string: "data:image/png;base64,dGVzdA==")!
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .file(.init(data: .url(url), filename: "test.png", mediaType: "image/png")),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .file(.init(data: .url(url), filename: "test.png", mediaType: "image/png")),
      ]),
    ])
  }

  func testAssistantMessage_toolOutputAvailable_producesToolRoleMessageAndPropagatesCallProviderMetadata() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "Let me calculate that for you.", state: .done)),
        .tool(.init(
          toolCallID: "call1",
          toolName: "calculator",
          input: .object(["operation": .string("add"), "numbers": .array([.number(1), .number(2)])]),
          output: .string("3"),
          callProviderMetadata: ["testProvider": .object(["signature": .string("1234567890")])],
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.assistant, .tool])

    guard case let .toolCall(call) = result[0].content.last else { return XCTFail("expected tool call") }
    XCTAssertEqual(call.toolCallID, "call1")
    XCTAssertEqual(call.toolName, "calculator")
    XCTAssertEqual(object(call.providerMetadata?["testProvider"])?["signature"], .string("1234567890"))

    guard case let .toolResult(toolResult) = result[1].content.first else { return XCTFail("expected tool result") }
    XCTAssertEqual(toolResult.toolCallID, "call1")
    XCTAssertEqual(toolResult.toolName, "calculator")
    XCTAssertEqual(toolResult.output, Self.toolOutputText("3"))
    XCTAssertEqual(object(toolResult.providerMetadata?["testProvider"])?["signature"], .string("1234567890"))
  }

  func testAssistantMessage_toolOutputError_withRawInput() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "Let me calculate that for you.", state: .done)),
        .tool(.init(
          toolCallID: "call1",
          toolName: "calculator",
          input: nil,
          rawInput: .object(["operation": .string("add"), "numbers": .array([.number(1), .number(2)])]),
          output: nil,
          state: .outputError(errorText: "Error: Invalid input")
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.assistant, .tool])

    guard case let .toolCall(call) = result[0].content.last else { return XCTFail("expected tool call") }
    XCTAssertEqual(call.input, .object(["operation": .string("add"), "numbers": .array([.number(1), .number(2)])]))

    guard case let .toolResult(toolResult) = result[1].content.first else { return XCTFail("expected tool result") }
    XCTAssertEqual(toolResult.output, toolOutputErrorText("Error: Invalid input"))
  }

  func testAssistantMessage_toolOutputError_withoutRawInput() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "Let me calculate that for you.", state: .done)),
        .tool(.init(
          toolCallID: "call1",
          toolName: "calculator",
          input: .object(["operation": .string("add"), "numbers": .array([.number(1), .number(2)])]),
          output: nil,
          state: .outputError(errorText: "Error: Invalid input")
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.assistant, .tool])

    guard case let .toolCall(call) = result[0].content.last else { return XCTFail("expected tool call") }
    XCTAssertEqual(call.input, .object(["operation": .string("add"), "numbers": .array([.number(1), .number(2)])]))
  }

  func testAssistantMessage_providerExecutedToolOutputAvailable() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "Let me calculate that for you.", state: .done)),
        .tool(.init(
          toolCallID: "call1",
          toolName: "calculator",
          providerExecuted: true,
          input: .object(["operation": .string("add"), "numbers": .array([.number(1), .number(2)])]),
          output: .string("3"),
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].role, .assistant)
    XCTAssertEqual(result[0].content.compactMap { part -> ToolResult? in
      guard case let .toolResult(r) = part else { return nil }
      return r
    }.first?.output, Self.toolOutputText("3"))
  }

  func testAssistantMessage_providerExecutedToolOutputError_isErrorJSON() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "Let me calculate that for you.", state: .done)),
        .tool(.init(
          toolCallID: "call1",
          toolName: "calculator",
          providerExecuted: true,
          input: .object(["operation": .string("add"), "numbers": .array([.number(1), .number(2)])]),
          output: nil,
          state: .outputError(errorText: "Error: Invalid input")
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 1)
    let toolResults = result[0].content.compactMap { part -> ToolResult? in
      guard case let .toolResult(r) = part else { return nil }
      return r
    }
    XCTAssertEqual(toolResults.count, 1)
    XCTAssertEqual(toolResults[0].output, toolOutputErrorJSON("Error: Invalid input"))
  }

  func testAssistantMessage_providerExecutedTool_propagatesProviderMetadataToToolResult() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call1",
          toolName: "calculator",
          providerExecuted: true,
          input: .object(["operation": .string("multiply"), "numbers": .array([.number(3), .number(4)])]),
          output: .string("12"),
          callProviderMetadata: ["testProvider": .object(["executionTime": .number(75)])],
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    let toolCalls = result[0].content.compactMap { part -> ToolCall? in
      guard case let .toolCall(c) = part else { return nil }
      return c
    }
    let toolResults = result[0].content.compactMap { part -> ToolResult? in
      guard case let .toolResult(r) = part else { return nil }
      return r
    }
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolResults.count, 1)
    XCTAssertEqual(object(toolCalls[0].providerMetadata?["testProvider"])?["executionTime"], .number(75))
    XCTAssertEqual(object(toolResults[0].providerMetadata?["testProvider"])?["executionTime"], .number(75))
  }

  func testAssistantMessage_toolInvocations_multiPartResponses_snapshotEquivalent() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "Let me calculate that for you.", state: .done)),
        .tool(.init(
          toolCallID: "call1",
          toolName: "screenshot",
          input: .object([:]),
          output: .string("imgbase64"),
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .text(.init(text: "Let me calculate that for you.")),
        .toolCall(.init(toolCallID: "call1", toolName: "screenshot", inputJSON: "", input: .object([:]))),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call1", toolName: "screenshot", output: Self.toolOutputText("imgbase64"))),
      ]),
    ])
  }

  func testAssistantMessage_conversationWithEmptyToolInvocations_snapshotEquivalent() async throws {
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "text1", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .text(.init(id: "t2", text: "text2", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .user, content: [.text(.init(text: "text1"))]),
      .init(role: .assistant, content: [.text(.init(text: "text2"))]),
    ])
  }

  func testAssistantMessage_multipleToolInvocationsWithStepInformation_snapshotEquivalent() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "response", state: .done)),
        .tool(.init(
          toolCallID: "call-1",
          toolName: "screenshot",
          input: .object(["value": .string("value-1")]),
          output: .string("result-1"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .tool(.init(
          toolCallID: "call-2",
          toolName: "screenshot",
          input: .object(["value": .string("value-2")]),
          output: .string("result-2"),
          state: .outputAvailable(preliminary: false)
        )),
        .tool(.init(
          toolCallID: "call-3",
          toolName: "screenshot",
          input: .object(["value": .string("value-3")]),
          output: .string("result-3"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .tool(.init(
          toolCallID: "call-4",
          toolName: "screenshot",
          input: .object(["value": .string("value-4")]),
          output: .string("result-4"),
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .text(.init(text: "response")),
        .toolCall(.init(toolCallID: "call-1", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-1")]))),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call-1", toolName: "screenshot", output: Self.toolOutputText("result-1"))),
      ]),
      .init(role: .assistant, content: [
        .toolCall(.init(toolCallID: "call-2", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-2")]))),
        .toolCall(.init(toolCallID: "call-3", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-3")]))),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call-2", toolName: "screenshot", output: Self.toolOutputText("result-2"))),
        .toolResult(.init(toolCallID: "call-3", toolName: "screenshot", output: Self.toolOutputText("result-3"))),
      ]),
      .init(role: .assistant, content: [
        .toolCall(.init(toolCallID: "call-4", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-4")]))),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call-4", toolName: "screenshot", output: Self.toolOutputText("result-4"))),
      ]),
    ])
  }

  func testAssistantMessage_mixOfToolInvocationsAndText_snapshotEquivalent() async throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t1", text: "i am gonna use tool1", state: .done)),
        .tool(.init(
          toolCallID: "call-1",
          toolName: "screenshot",
          input: .object(["value": .string("value-1")]),
          output: .string("result-1"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .text(.init(id: "t2", text: "i am gonna use tool2 and tool3", state: .done)),
        .tool(.init(
          toolCallID: "call-2",
          toolName: "screenshot",
          input: .object(["value": .string("value-2")]),
          output: .string("result-2"),
          state: .outputAvailable(preliminary: false)
        )),
        .tool(.init(
          toolCallID: "call-3",
          toolName: "screenshot",
          input: .object(["value": .string("value-3")]),
          output: .string("result-3"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .tool(.init(
          toolCallID: "call-4",
          toolName: "screenshot",
          input: .object(["value": .string("value-4")]),
          output: .string("result-4"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .text(.init(id: "t3", text: "final response", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .assistant, content: [
        .text(.init(text: "i am gonna use tool1")),
        .toolCall(.init(toolCallID: "call-1", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-1")]))),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call-1", toolName: "screenshot", output: Self.toolOutputText("result-1"))),
      ]),
      .init(role: .assistant, content: [
        .text(.init(text: "i am gonna use tool2 and tool3")),
        .toolCall(.init(toolCallID: "call-2", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-2")]))),
        .toolCall(.init(toolCallID: "call-3", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-3")]))),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call-2", toolName: "screenshot", output: Self.toolOutputText("result-2"))),
        .toolResult(.init(toolCallID: "call-3", toolName: "screenshot", output: Self.toolOutputText("result-3"))),
      ]),
      .init(role: .assistant, content: [
        .toolCall(.init(toolCallID: "call-4", toolName: "screenshot", inputJSON: "", input: .object(["value": .string("value-4")]))),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call-4", toolName: "screenshot", output: Self.toolOutputText("result-4"))),
      ]),
      .init(role: .assistant, content: [
        .text(.init(text: "final response")),
      ]),
    ])
  }

  func testAssistantMessage_withToolOutputProducesToolRoleMessage() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .tool(.init(
            toolCallID: "tool-1",
            toolName: "getLocation",
            providerExecuted: false,
            dynamic: false,
            input: .object([:]),
            output: .string("NYC"),
            state: .outputAvailable(preliminary: false)
          )),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result[0].role, .assistant)
    XCTAssertEqual(result[1].role, .tool)

    let toolMessage = result[1]
    guard toolMessage.content.contains(where: { part in
      if case let .toolResult(result) = part {
        return result.toolCallID == "tool-1" && result.output == Self.toolOutputText("NYC")
      }
      return false
    }) else {
      return XCTFail("expected toolResult in tool message")
    }
  }

  func testIgnoreIncompleteToolCalls_dropsInputStreamingAndInputAvailableToolParts() async throws {
    let messages: [ChatMessage] = [
      .init(
        id: "a1",
        role: .assistant,
        parts: [
          .tool(.init(toolCallID: "tool-1", toolName: "t", state: .inputStreaming)),
          .tool(.init(toolCallID: "tool-2", toolName: "t", state: .inputAvailable)),
          .tool(.init(
            toolCallID: "tool-3",
            toolName: "t",
            input: .object([:]),
            output: .string("ok"),
            state: .outputAvailable(preliminary: false)
          )),
        ]
      ),
    ]

    let result = try await convertToModelMessages(messages, options: .init(ignoreIncompleteToolCalls: true))
    XCTAssertEqual(result.count, 2) // assistant + tool
    let assistant = result[0]
    let toolCalls = assistant.content.compactMap { part -> ToolCall? in
      if case let .toolCall(call) = part { return call }
      return nil
    }
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolCalls.first?.toolCallID, "tool-3")
  }

  func testMultipleMessages_conversationWithMultipleTurns() async throws {
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What's the weather like?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .text(.init(id: "t2", text: "I'll check that for you.", state: .done)),
      ]),
      .init(id: "u2", role: .user, parts: [
        .text(.init(id: "t3", text: "Thanks!", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result, [
      .init(role: .user, content: [.text(.init(text: "What's the weather like?"))]),
      .init(role: .assistant, content: [.text(.init(text: "I'll check that for you."))]),
      .init(role: .user, content: [.text(.init(text: "Thanks!"))]),
    ])
  }

  func testMultipleMessages_multipleToolInvocationsAndUserMessageAtEnd() async throws {
    let assistant: ChatMessage = .init(
      id: "a1",
      role: .assistant,
      parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "screenshot",
          input: .object(["value": .string("value-1")]),
          output: .string("result-1"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .tool(.init(
          toolCallID: "call-2",
          toolName: "screenshot",
          input: .object(["value": .string("value-2")]),
          output: .string("result-2"),
          state: .outputAvailable(preliminary: false)
        )),
        .tool(.init(
          toolCallID: "call-3",
          toolName: "screenshot",
          input: .object(["value": .string("value-3")]),
          output: .string("result-3"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .tool(.init(
          toolCallID: "call-4",
          toolName: "screenshot",
          input: .object(["value": .string("value-4")]),
          output: .string("result-4"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .text(.init(id: "t1", text: "response", state: .done)),
      ]
    )

    let user: ChatMessage = .init(id: "u1", role: .user, parts: [
      .text(.init(id: "t2", text: "Thanks!", state: .done)),
    ])

    let result = try await convertToModelMessages([assistant, user], options: .init())
    XCTAssertEqual(result.map(\.role), [
      .assistant, .tool,
      .assistant, .tool,
      .assistant, .tool,
      .assistant,
      .user,
    ])
    XCTAssertEqual(result.count, 8)

    func toolCallIDs(in message: ModelMessage) -> [String] {
      message.content.compactMap { part in
        guard case let .toolCall(call) = part else { return nil }
        return call.toolCallID
      }
    }

    func toolResultIDs(in message: ModelMessage) -> [String] {
      message.content.compactMap { part in
        guard case let .toolResult(result) = part else { return nil }
        return result.toolCallID
      }
    }

    XCTAssertEqual(toolCallIDs(in: result[0]), ["call-1"])
    XCTAssertEqual(toolResultIDs(in: result[1]), ["call-1"])

    XCTAssertEqual(toolCallIDs(in: result[2]), ["call-2", "call-3"])
    XCTAssertEqual(toolResultIDs(in: result[3]), ["call-2", "call-3"])

    XCTAssertEqual(toolCallIDs(in: result[4]), ["call-4"])
    XCTAssertEqual(toolResultIDs(in: result[5]), ["call-4"])

    guard case let .text(text) = result[6].content.first else { return XCTFail("expected assistant text") }
    XCTAssertEqual(text.text, "response")
    guard case let .text(userText) = result[7].content.first else { return XCTFail("expected user text") }
    XCTAssertEqual(userText.text, "Thanks!")
  }

  func testErrorHandling_throwsForUnsupportedChatMessageRole() async {
    let messages: [ChatMessage] = [
      .init(id: "t1", role: .tool, parts: [.text(.init(id: "x", text: "unsupported", state: .done))]),
    ]

    do {
      _ = try await convertToModelMessages(messages, options: .init())
      XCTFail("Expected error")
    } catch {
      XCTAssertTrue(String(describing: error).contains("Unsupported ChatMessage role: tool"))
    }
  }

  func testConvertDynamicToolInvocation() async throws {
    let assistant: ChatMessage = .init(id: "a1", role: .assistant, parts: [
      .stepStart,
      .tool(.init(
        toolCallID: "call-1",
        toolName: "screenshot",
        dynamic: true,
        input: .object(["value": .string("value-1")]),
        output: .string("result-1"),
        state: .outputAvailable(preliminary: false)
      )),
    ])
    let user: ChatMessage = .init(id: "u1", role: .user, parts: [
      .text(.init(id: "t1", text: "Thanks!", state: .done)),
    ])

    let result = try await convertToModelMessages([assistant, user], options: .init(ignoreIncompleteToolCalls: true))
    XCTAssertEqual(result.map(\.role), [.assistant, .tool, .user])

    guard case let .toolCall(call) = result[0].content.first else { return XCTFail("expected tool call") }
    XCTAssertEqual(call.toolCallID, "call-1")
    XCTAssertEqual(call.toolName, "screenshot")
    XCTAssertEqual(call.dynamic, true)

    guard case let .toolResult(toolResult) = result[1].content.first else { return XCTFail("expected tool result") }
    XCTAssertEqual(toolResult.toolCallID, "call-1")
    XCTAssertEqual(toolResult.output, Self.toolOutputText("result-1"))
  }

  func testConvertProviderExecutedDynamicToolInvocation_inAssistantContent_andNoToolRoleMessage() async throws {
    let assistant: ChatMessage = .init(id: "a1", role: .assistant, parts: [
      .stepStart,
      .tool(.init(
        toolCallID: "call-1",
        toolName: "screenshot",
        providerExecuted: true,
        dynamic: true,
        input: .object(["value": .string("value-1")]),
        output: .string("result-1"),
        callProviderMetadata: ["test-provider": .object(["key-a": .string("test-value-1"), "key-b": .string("test-value-2")])],
        state: .outputAvailable(preliminary: false)
      )),
    ])
    let user: ChatMessage = .init(id: "u1", role: .user, parts: [
      .text(.init(id: "t1", text: "Thanks!", state: .done)),
    ])

    let result = try await convertToModelMessages([assistant, user], options: .init(ignoreIncompleteToolCalls: true))
    XCTAssertEqual(result.map(\.role), [.assistant, .user])

    let toolCalls = result[0].content.compactMap { part -> ToolCall? in
      guard case let .toolCall(call) = part else { return nil }
      return call
    }
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolCalls[0].providerExecuted, true)
    XCTAssertEqual(toolCalls[0].dynamic, true)
    XCTAssertEqual(object(toolCalls[0].providerMetadata?["test-provider"])?["key-a"], .string("test-value-1"))

    let toolResults = result[0].content.compactMap { part -> ToolResult? in
      guard case let .toolResult(result) = part else { return nil }
      return result
    }
    XCTAssertEqual(toolResults.count, 1)
    XCTAssertEqual(toolResults[0].providerExecuted, true)
    XCTAssertEqual(toolResults[0].dynamic, true)
    XCTAssertEqual(object(toolResults[0].providerMetadata?["test-provider"])?["key-b"], .string("test-value-2"))
    XCTAssertEqual(toolResults[0].output, Self.toolOutputText("result-1"))
  }

  func testToolApprovalRequestResponses_approvedStaticTool() async throws {
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          input: .object(["city": .string("Tokyo")]),
          approval: .init(id: "approval-1", approved: true, reason: nil),
          state: .approvalResponded(approvalID: "approval-1", approved: true, reason: nil)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool])

    XCTAssertEqual(result[1].content.compactMap { part -> ToolApprovalRequest? in
      guard case let .toolApprovalRequest(r) = part else { return nil }
      return r
    }, [.init(approvalID: "approval-1", toolCallID: "call-1")])

    XCTAssertEqual(result[2].content.compactMap { part -> ToolApprovalResponse? in
      guard case let .toolApprovalResponse(r) = part else { return nil }
      return r
    }, [.init(approvalID: "approval-1", approved: true, reason: nil)])
  }

  func testToolApprovalRequestResponses_approvedDynamicTool() async throws {
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          dynamic: true,
          input: .object(["city": .string("Tokyo")]),
          approval: .init(id: "approval-1", approved: true, reason: nil),
          state: .approvalResponded(approvalID: "approval-1", approved: true, reason: nil)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool])

    let toolCalls = result[1].content.compactMap { part -> ToolCall? in
      guard case let .toolCall(c) = part else { return nil }
      return c
    }
    XCTAssertEqual(toolCalls.first?.dynamic, true)
  }

  func testToolApprovalRequestResponses_deniedStaticTool_followUpText() async throws {
    let denial = "I don't want to approve this"
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          input: .object(["city": .string("Tokyo")]),
          approval: .init(id: "approval-1", approved: false, reason: denial),
          state: .approvalResponded(approvalID: "approval-1", approved: false, reason: denial)
        )),
        .stepStart,
        .text(.init(id: "t2", text: "I was not able to retrieve the weather.", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool, .assistant])
    guard case let .text(text) = result[3].content.first else { return XCTFail("expected follow up text") }
    XCTAssertEqual(text.text, "I was not able to retrieve the weather.")
  }

  func testToolApprovalRequestResponses_deniedDynamicTool_followUpText() async throws {
    let denial = "I don't want to approve this"
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          dynamic: true,
          input: .object(["city": .string("Tokyo")]),
          approval: .init(id: "approval-1", approved: false, reason: denial),
          state: .approvalResponded(approvalID: "approval-1", approved: false, reason: denial)
        )),
        .stepStart,
        .text(.init(id: "t2", text: "I was not able to retrieve the weather.", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool, .assistant])
  }

  func testToolApprovalRequestResponses_toolOutputDenied_staticTool() async throws {
    let denial = "I don't want to approve this"
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          input: .object(["city": .string("Tokyo")]),
          approval: .init(id: "approval-1", approved: false, reason: denial),
          state: .outputDenied(approvalID: "approval-1", reason: denial)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool])

    let toolMessage = result[2]
    XCTAssertEqual(toolMessage.content.compactMap { part -> ToolApprovalResponse? in
      guard case let .toolApprovalResponse(r) = part else { return nil }
      return r
    }, [.init(approvalID: "approval-1", approved: false, reason: denial)])

    XCTAssertEqual(toolMessage.content.compactMap { part -> ToolResult? in
      guard case let .toolResult(r) = part else { return nil }
      return r
    }, [
      .init(toolCallID: "call-1", toolName: "weather", output: toolOutputErrorText(denial)),
    ])
  }

  func testToolApprovalRequestResponses_toolOutputDenied_dynamicTool() async throws {
    let denial = "I don't want to approve this"
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          dynamic: true,
          input: .object(["city": .string("Tokyo")]),
          approval: .init(id: "approval-1", approved: false, reason: denial),
          state: .outputDenied(approvalID: "approval-1", reason: denial)
        )),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool])
  }

  func testToolApprovalRequestResponses_toolOutputAvailableWithApproval_followUpText_staticTool() async throws {
    let output = JSONValue.object(["weather": .string("Sunny"), "temperature": .string("20°C")])
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          input: .object(["city": .string("Tokyo")]),
          output: output,
          approval: .init(id: "approval-1", approved: true, reason: nil),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .text(.init(id: "t2", text: "The weather in Tokyo is sunny.", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool, .assistant])

    let toolMessage = result[2]
    XCTAssertEqual(toolMessage.content.compactMap { part -> ToolApprovalResponse? in
      guard case let .toolApprovalResponse(r) = part else { return nil }
      return r
    }, [.init(approvalID: "approval-1", approved: true, reason: nil)])

    let results = toolMessage.content.compactMap { part -> ToolResult? in
      guard case let .toolResult(r) = part else { return nil }
      return r
    }
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results[0].toolCallID, "call-1")
    XCTAssertEqual(results[0].output, toolOutputJSON(output))
  }

  func testToolApprovalRequestResponses_toolOutputErrorWithApproval_followUpText_staticTool() async throws {
    let err = "Error: Fetching weather data failed"
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [
        .text(.init(id: "t1", text: "What is the weather in Tokyo?", state: .done)),
      ]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "weather",
          input: .object(["city": .string("Tokyo")]),
          output: nil,
          approval: .init(id: "approval-1", approved: true, reason: nil),
          state: .outputError(errorText: err)
        )),
        .stepStart,
        .text(.init(id: "t2", text: "The weather in Tokyo is sunny.", state: .done)),
      ]),
    ]

    let result = try await convertToModelMessages(messages, options: .init())
    XCTAssertEqual(result.map(\.role), [.user, .assistant, .tool, .assistant])

    let toolMessage = result[2]
    let results = toolMessage.content.compactMap { part -> ToolResult? in
      guard case let .toolResult(r) = part else { return nil }
      return r
    }
    XCTAssertEqual(results, [.init(toolCallID: "call-1", toolName: "weather", output: toolOutputErrorText(err))])
  }
}
