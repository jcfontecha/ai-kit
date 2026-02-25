import XCTest
@testable import AIKitProviders

final class AIKitProvidersTests: XCTestCase {
  func testAIKitErrorLocalizedDescriptionUsesMessage() {
    XCTAssertEqual(AIKitError.notImplemented("nope").localizedDescription, "nope")
    XCTAssertEqual(AIKitError.invalidConfiguration("bad").localizedDescription, "bad")
  }

  func testJSONValueCodableRoundTrip() throws {
    let value: JSONValue = .object(["a": .array([.string("b"), .number(1)])])
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, value)
  }
}
