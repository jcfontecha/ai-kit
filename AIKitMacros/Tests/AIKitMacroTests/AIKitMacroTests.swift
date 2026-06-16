import XCTest
import AIKitMacro

@AIModel
private struct MacroPerson: Sendable, Codable {
  @Field("Full name", minLength: 1)
  let name: String

  @Field("Age in years", range: 0...150)
  let age: Int

  let email: String?
}

@AIModel
private struct MacroMultilineDescription: Sendable, Codable {
  @Field(
    "first part "
      + "second part "
      + "third part"
  )
  let field: String
}

final class AIKitMacroTests: XCTestCase {
  func testMacroCompiles() throws {
    _ = MacroPerson.schema
  }

  /// A multi-line `"a" + "b"` description must be concatenated into its value, not
  /// leaked as `a" + "b` source text into the generated schema.
  func testMultilineFieldDescriptionConcatenates() throws {
    let json = MacroMultilineDescription.schema.jsonSchema.value
    guard case let .object(properties)? = json["properties"],
          case let .object(field)? = properties["field"],
          case let .string(description)? = field["description"]
    else {
      return XCTFail("expected a string description on `field`")
    }
    XCTAssertEqual(description, "first part second part third part")
    XCTAssertFalse(description.contains("+ \""), "description leaked concatenation source text")
  }
}

