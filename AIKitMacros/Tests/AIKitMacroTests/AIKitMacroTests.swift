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

final class AIKitMacroTests: XCTestCase {
  func testMacroCompiles() throws {
    _ = MacroPerson.schema
  }
}

