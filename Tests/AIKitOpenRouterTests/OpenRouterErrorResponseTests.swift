import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterErrorResponseTests: XCTestCase {
  private struct ErrorEnvelope: Decodable {
    let error: OpenRouterErrorPayload
    let userId: String?

    enum CodingKeys: String, CodingKey {
      case error
      case userId = "user_id"
    }
  }

  func testErrorResponseDefaults() throws {
    let payload = """
    {
      "error": {
        "message": "Example error message",
        "metadata": { "provider_name": "Example Provider" }
      },
      "user_id": "example_1"
    }
    """.data(using: .utf8)!

    let decoded = try OpenRouterJSON.decoder.decode(ErrorEnvelope.self, from: payload)
    XCTAssertEqual(decoded.error.message, "Example error message")
    XCTAssertNil(decoded.error.code)
    XCTAssertNil(decoded.error.type)
    XCTAssertNil(decoded.error.param)
    XCTAssertEqual(decoded.userId, "example_1")
  }

  func testErrorResponseWithTypeAndCode() throws {
    let payload = """
    {
      "error": {
        "message": "Example error message with type",
        "type": "invalid_request_error",
        "code": 400,
        "param": "canBeAnything",
        "metadata": { "provider_name": "Example Provider" }
      }
    }
    """.data(using: .utf8)!

    let decoded = try OpenRouterJSON.decoder.decode(ErrorEnvelope.self, from: payload)
    XCTAssertEqual(decoded.error.message, "Example error message with type")
    XCTAssertNotNil(decoded.error.code)
    if case let .number(code)? = decoded.error.code {
      XCTAssertEqual(code, 400)
    } else {
      XCTFail("Expected numeric code")
    }
    XCTAssertEqual(decoded.error.type, "invalid_request_error")
    if case let .string(param)? = decoded.error.param {
      XCTAssertEqual(param, "canBeAnything")
    } else {
      XCTFail("Expected param string")
    }
  }
}
