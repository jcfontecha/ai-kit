import XCTest
import AIKitProviders
@testable @_spi(Advanced) import AIKit
import AIKitTestKit

final class OutputSpecTests: XCTestCase {
  private let context = OutputContext(
    finishReason: .length,
    usage: Usage(
      inputTokens: .init(total: 1, noCache: 1, cacheRead: nil, cacheWrite: nil),
      outputTokens: .init(total: 2, text: 2, reasoning: nil)
    ),
    providerMetadata: nil,
    response: LanguageModelResponseMetadata(
      id: "123",
      modelID: "456",
      timestamp: Date(timeIntervalSince1970: 0),
      headers: nil,
      body: nil
    )
  )

  func testOutputText_responseFormat_isText() {
    XCTAssertEqual(Output.text().responseFormat, .text)
  }

  func testOutputText_parseComplete_returnsText() async throws {
    let result = try await Output.text().parseComplete(text: "some output", context: context)
    XCTAssertEqual(result, "some output")
  }

  func testOutputText_parseComplete_handlesEmptyString() async throws {
    let result = try await Output.text().parseComplete(text: "", context: context)
    XCTAssertEqual(result, "")
  }

  func testOutputText_parsePartial_returnsPartialString() async {
    let result = await Output.text().parsePartial(text: "partial text")
    XCTAssertEqual(result, "partial text")
  }

  func testOutputText_parsePartial_handlesEmptyString() async {
    let result = await Output.text().parsePartial(text: "")
    XCTAssertEqual(result, "")
  }

  func testOutputJSON_responseFormat_includesNameAndDescription() {
    XCTAssertEqual(
      Output.json(name: "test-name", description: "test description").responseFormat,
      .json(name: "test-name", description: "test description")
    )
  }

  func testOutputJSON_parseComplete_parsesValidJSON() async throws {
    let result = try await Output.json().parseComplete(
      text: "{\"a\": 1, \"b\": [2, 3]}",
      context: context
    )
    XCTAssertEqual(
      result,
      .object(["a": .number(1), "b": .array([.number(2), .number(3)])])
    )
  }

  func testOutputJSON_parseComplete_throwsOnInvalidJSON() async {
    do {
      _ = try await Output.json().parseComplete(text: "{ a: 1 }", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: could not parse the response.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputJSON_parseComplete_throwsOnPlainText() async {
    do {
      _ = try await Output.json().parseComplete(text: "foo", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: could not parse the response.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputJSON_parsePartial_validJSON() async {
    let result = await Output.json().parsePartial(text: "{ \"foo\": 1, \"bar\": [2, 3] }")
    XCTAssertEqual(
      result,
      .object(["foo": .number(1), "bar": .array([.number(2), .number(3)])])
    )
  }

  func testOutputJSON_parsePartial_repairableJSON() async {
    let result = await Output.json().parsePartial(text: "{ \"foo\": 123")
    XCTAssertNotNil(result)
  }

  func testOutputJSON_parsePartial_invalidReturnsNil() async {
    let result = await Output.json().parsePartial(text: "invalid!")
    XCTAssertNil(result)
  }

  func testOutputJSON_parsePartial_emptyStringReturnsNil() async {
    let result = await Output.json().parsePartial(text: "")
    XCTAssertNil(result)
  }

  func testOutputJSON_parsePartial_undefinedReturnsNil() async {
    let result = await Output.json().parsePartial(text: "undefined")
    XCTAssertNil(result)
  }

  func testOutputObject_responseFormat_matchesDraft07Schema() throws {
    struct Person: Codable, Sendable {
      let content: String
    }

    let schema = ObjectSchema<Person>.manual(
      jsonSchema: .object(
        properties: [
          "content": .string(),
        ],
        required: ["content"],
        additionalProperties: false
      ),
      name: "Person",
      description: nil
    )

    let output = Output.object(Person.self, schema: schema)

    guard case let .jsonSchema(jsonSchema, name, description) = output.responseFormat else {
      return XCTFail("Expected .jsonSchema response format")
    }

    XCTAssertEqual(name, "Person")
    XCTAssertNil(description)

    SnapshotTesting.assertSnapshot(jsonSchema, testName: "Person.jsonSchema")
  }

  func testOutputObject_parseComplete_parsesValidObject() async throws {
    struct Person: Codable, Sendable, Equatable {
      let content: String
    }

    let schema = ObjectSchema<Person>.manual(
      jsonSchema: .object(
        properties: [
          "content": .string(),
        ],
        required: ["content"],
        additionalProperties: false
      ),
      name: "Person",
      description: nil
    )

    let output = Output.object(Person.self, schema: schema)
    let result = try await output.parseComplete(text: "{ \"content\": \"test\" }", context: context)
    XCTAssertEqual(result, Person(content: "test"))
  }

  func testOutputObject_parseComplete_throwsOnInvalidJSON() async {
    struct Person: Codable, Sendable {
      let content: String
    }
    let output = Output.object(
      Person.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Person"
      )
    )

    do {
      _ = try await output.parseComplete(text: "{ broken json", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: could not parse the response.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputObject_parseComplete_throwsOnSchemaMismatch() async {
    struct Person: Codable, Sendable {
      let content: String
    }
    let output = Output.object(
      Person.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Person"
      )
    )

    do {
      _ = try await output.parseComplete(text: "{ \"content\": 123 }", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: response did not match schema.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputObject_parsePartial_validJSON() async {
    struct Person: Codable, Sendable {
      let content: String
    }
    let output = Output.object(
      Person.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Person"
      )
    )

    let result = await output.parsePartial(text: "{ \"content\": \"test\" }")
    XCTAssertEqual(result, .object(["content": .string("test")]))
  }

  func testOutputObject_parsePartial_repairableJSON() async {
    struct Person: Codable, Sendable {
      let content: String
    }
    let output = Output.object(
      Person.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Person"
      )
    )

    let result = await output.parsePartial(text: "{ \"content\": \"test\"")
    XCTAssertEqual(result, .object(["content": .string("test")]))
  }

  func testOutputObject_parsePartial_missingClosingBrace() async {
    struct Person: Codable, Sendable {
      let content: String
      let count: Int
    }
    let output = Output.object(
      Person.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["content": .string(), "count": .number()],
          required: ["content", "count"],
          additionalProperties: false
        ),
        name: "Person"
      )
    )

    let result = await output.parsePartial(text: "{ \"content\": \"partial\", \"count\": 42")
    XCTAssertEqual(
      result,
      .object(["content": .string("partial"), "count": .number(42)])
    )
  }

  func testOutputObject_parsePartial_handlesArray() async {
    struct Items: Codable, Sendable {
      let items: [String]
    }
    let output = Output.object(
      Items.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["items": .array(items: .string())],
          required: ["items"],
          additionalProperties: false
        ),
        name: "Items"
      )
    )

    let result = await output.parsePartial(text: "{ \"items\": [\"a\", \"b\"")
    XCTAssertEqual(
      result,
      .object(["items": .array([.string("a"), .string("b")])])
    )
  }

  func testOutputObject_parsePartial_emptyStringReturnsNil() async {
    struct Person: Codable, Sendable {
      let content: String
    }
    let output = Output.object(
      Person.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Person"
      )
    )

    let result = await output.parsePartial(text: "")
    XCTAssertNil(result)
  }

  func testOutputObject_parsePartial_partialStringValue() async {
    struct Person: Codable, Sendable {
      let content: String
    }
    let output = Output.object(
      Person.self,
      schema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Person"
      )
    )

    let result = await output.parsePartial(text: "{ \"content\": \"partial str")
    XCTAssertEqual(result, .object(["content": .string("partial str")]))
  }

  func testOutputArray_responseFormat_wrapsElementsInObject() throws {
    struct Item: Codable, Sendable {
      let content: String
    }

    let itemSchema = ObjectSchema<Item>.manual(
      jsonSchema: .object(
        properties: [
          "content": .string(),
        ],
        required: ["content"],
        additionalProperties: false
      ),
      name: "Item",
      description: nil
    )

    let output = Output.array(Item.self, elementSchema: itemSchema, name: "items", description: "desc")

    guard case let .jsonSchema(jsonSchema, name, description) = output.responseFormat else {
      return XCTFail("Expected .jsonSchema response format")
    }

    XCTAssertEqual(name, "items")
    XCTAssertEqual(description, "desc")

    SnapshotTesting.assertSnapshot(jsonSchema, testName: "Array.jsonSchema")
  }

  func testOutputArray_parseComplete_parsesValidArray() async throws {
    struct Item: Codable, Sendable, Equatable {
      let content: String
    }

    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )

    let result = try await output.parseComplete(
      text: "{ \"elements\": [{ \"content\": \"test\" }] }",
      context: context
    )
    XCTAssertEqual(result, [Item(content: "test")])
  }

  func testOutputArray_parseComplete_throwsOnInvalidJSON() async {
    struct Item: Codable, Sendable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )

    do {
      _ = try await output.parseComplete(text: "{ broken json", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: could not parse the response.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputArray_parseComplete_throwsOnSchemaMismatch() async {
    struct Item: Codable, Sendable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )

    do {
      _ = try await output.parseComplete(
        text: "{ \"elements\": [{ \"content\": 123 }] }",
        context: context
      )
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: response did not match schema.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputArray_parsePartial_validArray() async {
    struct Item: Codable, Sendable, Equatable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )

    let result = await output.parsePartial(
      text: "{ \"elements\": [{ \"content\": \"a\" }, { \"content\": \"b\" }] }"
    )
    XCTAssertEqual(result, [Item(content: "a"), Item(content: "b")])
  }

  func testOutputArray_parsePartial_repairedDropsIncompleteLastElement() async {
    struct Item: Codable, Sendable, Equatable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )

    let result = await output.parsePartial(
      text: "{ \"elements\": [{ \"content\": \"a\" }, { \"content\": \"b\" }"
    )
    XCTAssertEqual(result, [Item(content: "a")])
  }

  func testOutputArray_parsePartial_invalidReturnsNil() async {
    struct Item: Codable, Sendable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )

    let result = await output.parsePartial(text: "{ not valid json")
    XCTAssertNil(result)
  }

  func testOutputArray_parsePartial_emptyStringReturnsNil() async {
    struct Item: Codable, Sendable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )
    let result = await output.parsePartial(text: "")
    XCTAssertNil(result)
  }

  func testOutputArray_parsePartial_missingElementsReturnsNil() async {
    struct Item: Codable, Sendable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )
    let result = await output.parsePartial(text: "{ \"foo\": [1,2,3] }")
    XCTAssertNil(result)
  }

  func testOutputArray_parsePartial_elementsNotArrayReturnsNil() async {
    struct Item: Codable, Sendable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )
    let result = await output.parsePartial(text: "{ \"elements\": \"not-an-array\" }")
    XCTAssertNil(result)
  }

  func testOutputArray_parsePartial_emptyArrayReturnsEmpty() async {
    struct Item: Codable, Sendable, Equatable {
      let content: String
    }
    let output = Output.array(
      Item.self,
      elementSchema: .manual(
        jsonSchema: .object(
          properties: ["content": .string()],
          required: ["content"],
          additionalProperties: false
        ),
        name: "Item"
      )
    )
    let result = await output.parsePartial(text: "{ \"elements\": [] }")
    XCTAssertEqual(result, [])
  }

  func testOutputChoice_responseFormat_wrapsResultInObject() throws {
    let output = Output.choice(options: ["aaa", "aab", "ccc"], name: "test-choice", description: "desc")

    guard case let .jsonSchema(jsonSchema, name, description) = output.responseFormat else {
      return XCTFail("Expected .jsonSchema response format")
    }

    XCTAssertEqual(name, "test-choice")
    XCTAssertEqual(description, "desc")

    SnapshotTesting.assertSnapshot(jsonSchema, testName: "Choice.jsonSchema")
  }

  func testOutputChoice_parseComplete_validChoice() async throws {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = try await output.parseComplete(text: "{ \"result\": \"aaa\" }", context: context)
    XCTAssertEqual(result, "aaa")
  }

  func testOutputChoice_parseComplete_invalidJSONThrows() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    do {
      _ = try await output.parseComplete(text: "{ broken json", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: could not parse the response.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputChoice_parseComplete_missingResultThrows() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    do {
      _ = try await output.parseComplete(text: "{}", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: response did not match schema.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputChoice_parseComplete_invalidChoiceThrows() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    do {
      _ = try await output.parseComplete(text: "{ \"result\": \"d\" }", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: response did not match schema.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputChoice_parseComplete_nonStringThrows() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    do {
      _ = try await output.parseComplete(text: "{ \"result\": 5 }", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: response did not match schema.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputChoice_parseComplete_nonObjectThrows() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    do {
      _ = try await output.parseComplete(text: "\"a\"", context: context)
      XCTFail("Expected NoObjectGeneratedError")
    } catch let error as NoObjectGeneratedError {
      XCTAssertEqual(error.message, "No object generated: response did not match schema.")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOutputChoice_parsePartial_validExact() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ \"result\": \"aaa\" }")
    XCTAssertEqual(result, "aaa")
  }

  func testOutputChoice_parsePartial_invalidJSONReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ broken json")
    XCTAssertNil(result)
  }

  func testOutputChoice_parsePartial_missingResultReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{}")
    XCTAssertNil(result)
  }

  func testOutputChoice_parsePartial_ambiguousPrefixReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ \"result\": \"")
    XCTAssertNil(result)
  }

  func testOutputChoice_parsePartial_singlePrefixReturnsMatch() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ \"result\": \"c")
    XCTAssertEqual(result, "ccc")
  }

  func testOutputChoice_parsePartial_noMatchReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ \"result\": \"z\" }")
    XCTAssertNil(result)
  }

  func testOutputChoice_parsePartial_nonStringReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ \"result\": 5 }")
    XCTAssertNil(result)
  }

  func testOutputChoice_parsePartial_nonObjectReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "\"a\"")
    XCTAssertNil(result)
  }

  func testOutputChoice_parsePartial_fullMatchReturnsMatch() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ \"result\": \"aab\" }")
    XCTAssertEqual(result, "aab")
  }

  func testOutputChoice_parsePartial_prefixMatchesMultipleReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "{ \"result\": \"a")
    XCTAssertNil(result)
  }

  func testOutputChoice_parsePartial_nullReturnsNil() async {
    let output = Output.choice(options: ["aaa", "aab", "ccc"])
    let result = await output.parsePartial(text: "null")
    XCTAssertNil(result)
  }
}
