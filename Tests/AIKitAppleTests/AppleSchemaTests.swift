import XCTest
import FoundationModels
import AIKitProviders
@testable import AIKitApple

final class AppleSchemaTests: XCTestCase {
  func testNormalizeSchemaAddsXOrderAndAdditionalProperties() throws {
    let raw: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")]),
        "meta": .object([
          "type": .string("object"),
          "properties": .object([
            "age": .object(["type": .string("number")]),
          ]),
        ]),
      ]),
      "required": .array([.string("name")]),
    ])

    let normalized = appleNormalizeSchemaValue(raw, rootTitle: "Person")

    guard case .object(let root) = normalized else {
      XCTFail("Expected object schema")
      return
    }
    XCTAssertEqual(root["title"], .string("Person"))
    XCTAssertEqual(root["additionalProperties"], .bool(false))
    XCTAssertEqual(root["x-order"], .array([.string("meta"), .string("name")]))

    guard case let .object(properties)? = root["properties"],
          case let .object(meta)? = properties["meta"] else {
      XCTFail("Expected nested object schema")
      return
    }
    XCTAssertEqual(meta["additionalProperties"], .bool(false))
    XCTAssertEqual(meta["x-order"], .array([.string("age")]))
  }

  func testGenerationSchemaConvertsFromJSONSchema() throws {
    let schema = JSONSchema([
      "type": .string("object"),
      "properties": .object([
        "value": .object(["type": .string("string")]),
      ]),
      "required": .array([.string("value")]),
    ])

    let generationSchema = try appleGenerationSchema(from: schema, defaultName: "Root")
    let encoded = try JSONEncoder().encode(generationSchema)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)

    guard case .object(let object) = decoded else {
      XCTFail("Expected encoded schema object")
      return
    }
    XCTAssertEqual(object["title"], .string("Root"))
    XCTAssertEqual(object["x-order"], .array([.string("value")]))
  }

  func testJSONValueGeneratedContentRoundTrip() {
    let value: JSONValue = .object([
      "name": .string("A"),
      "scores": .array([.number(1), .number(2)]),
      "active": .bool(true),
    ])

    let generated = appleGeneratedContent(from: value)
    let roundTrip = appleJSONValue(from: generated)

    XCTAssertEqual(roundTrip, value)
  }
}
