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

  // MARK: - TypedObject

  func testOutputTypedObject_parseComplete_decodesObject() async throws {
    let result = try await Output.typedObject(ExercisePayload.self)
      .parseComplete(text: exercisePayloadFinalJSON, context: context)
    XCTAssertEqual(result, ExercisePayload.expectedFinal)
  }

  func testOutputTypedObject_parsePartial_completeJSON() async {
    let partial = await Output.typedObject(ExercisePayload.self)
      .parsePartial(text: exercisePayloadFinalJSON)
    XCTAssertEqual(partial?.name, ExercisePayload.expectedFinal.name)
    XCTAssertEqual(partial?.about, ExercisePayload.expectedFinal.about)
    XCTAssertEqual(partial?.steps, ExercisePayload.expectedFinal.steps)
    XCTAssertEqual(partial?.primaryMuscles, ExercisePayload.expectedFinal.primaryMuscles)
    XCTAssertEqual(partial?.defaultSets, 3)
    XCTAssertNil(partial?.defaultWeight)
  }

  func testOutputTypedObject_parsePartial_emptyStringReturnsNil() async {
    let result = await Output.typedObject(ExercisePayload.self).parsePartial(text: "")
    XCTAssertNil(result)
  }

  func testOutputTypedObject_parsePartial_invalidReturnsNil() async {
    let result = await Output.typedObject(ExercisePayload.self).parsePartial(text: "undefined")
    XCTAssertNil(result)
  }

  /// Streams the payload one character at a time and checks every snapshot:
  /// each decoded field must be a (string-)prefix of its final value, arrays
  /// must be element-wise prefixes, and the decode must never trap. This is
  /// the incremental-streaming behavior the single-delta E2E test never
  /// exercised.
  func testOutputTypedObject_parsePartial_prefixSweep() async throws {
    let output = Output.typedObject(ExercisePayload.self)
    let final = ExercisePayload.expectedFinal

    var snapshots = 0
    var sawTruncatedName = false
    var sawTruncatedStep = false

    for end in exercisePayloadFinalJSON.indices {
      let prefix = String(exercisePayloadFinalJSON[..<end])
      guard let partial = await output.parsePartial(text: prefix) else { continue }
      snapshots += 1

      if let name = partial.name {
        XCTAssertTrue(
          final.name.hasPrefix(name),
          "name \"\(name)\" is not a prefix of \"\(final.name)\" for input prefix: \(prefix)"
        )
        if name != final.name { sawTruncatedName = true }
      }
      if let about = partial.about {
        XCTAssertTrue(
          final.about.hasPrefix(about),
          "about \"\(about)\" is not a prefix of the final about for input prefix: \(prefix)"
        )
      }
      if let steps = partial.steps {
        XCTAssertLessThanOrEqual(steps.count, final.steps.count, "for input prefix: \(prefix)")
        for (index, step) in steps.enumerated() {
          if index < steps.count - 1 {
            XCTAssertEqual(step, final.steps[index], "for input prefix: \(prefix)")
          } else {
            XCTAssertTrue(
              final.steps[index].hasPrefix(step),
              "step \"\(step)\" is not a prefix of \"\(final.steps[index])\" for input prefix: \(prefix)"
            )
            if step != final.steps[index] { sawTruncatedStep = true }
          }
        }
      }
      if let muscles = partial.primaryMuscles {
        XCTAssertLessThanOrEqual(muscles.count, final.primaryMuscles.count)
        for (index, muscle) in muscles.enumerated() {
          XCTAssertTrue(final.primaryMuscles[index].hasPrefix(muscle), "for input prefix: \(prefix)")
        }
      }
      if let sets = partial.defaultSets {
        XCTAssertTrue("3".hasPrefix(String(sets)), "for input prefix: \(prefix)")
      }
    }

    let full = await output.parsePartial(text: exercisePayloadFinalJSON)
    XCTAssertEqual(full?.name, final.name)
    XCTAssertEqual(full?.steps, final.steps)

    XCTAssertGreaterThan(snapshots, 50, "expected partial snapshots throughout the stream")
    XCTAssertTrue(sawTruncatedName, "the sweep never observed a mid-value name — test is not exercising truncation")
    XCTAssertTrue(sawTruncatedStep, "the sweep never observed a mid-value step — test is not exercising truncation")
  }
}

// MARK: - TypedObject fixture (hand-written SchemaProviding, mirrors @AIModel output)

private struct ExercisePayload: SchemaProviding, Equatable {
  let name: String
  let about: String
  let steps: [String]
  let primaryMuscles: [String]
  let defaultSets: Int?
  let defaultWeight: Double?

  struct Partial: Codable, Sendable, Equatable {
    var name: String?
    var about: String?
    var steps: [String]?
    var primaryMuscles: [String]?
    var defaultSets: Int?
    var defaultWeight: Double?
  }

  static var schema: ObjectSchema<ExercisePayload> {
    .manual(
      jsonSchema: .object(
        properties: [
          "name": .string(),
          "about": .string(),
          "steps": .array(items: .string()),
          "primaryMuscles": .array(items: .string()),
          "defaultSets": .integer(),
          "defaultWeight": .number(),
        ],
        required: ["name", "about", "steps", "primaryMuscles"],
        additionalProperties: false
      ),
      name: "ExercisePayload"
    )
  }

  static let expectedFinal = ExercisePayload(
    name: "Bulgarian Split Squat",
    about: "A unilateral \"knee-dominant\" leg builder — brutal but effective 💪.",
    steps: [
      "Stand a stride length in front of a bench",
      "Place your rear foot on the bench",
      "Lower until the front thigh is parallel",
      "Drive through the front heel to stand",
    ],
    primaryMuscles: ["quads", "glutes"],
    defaultSets: 3,
    defaultWeight: nil
  )
}

private let exercisePayloadFinalJSON =
  #"{"name":"Bulgarian Split Squat","about":"A unilateral \"knee-dominant\" leg builder — brutal but effective 💪.","steps":["Stand a stride length in front of a bench","Place your rear foot on the bench","Lower until the front thigh is parallel","Drive through the front heel to stand"],"primaryMuscles":["quads","glutes"],"defaultSets":3,"defaultWeight":null}"#
