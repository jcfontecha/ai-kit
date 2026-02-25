import XCTest
@testable import AIKitFal

final class FalProviderTests: XCTestCase {
  func testCreateFal_buildsProvider() {
    let provider = createFal(.init(apiKey: "test-api-key"))
    _ = provider.image("fal-ai/flux/dev")
  }

  func testCreateFal_buildsWithCustomBaseURL() {
    let provider = createFal(.init(apiKey: "test-api-key", baseURL: "https://custom.fal.run"))
    _ = provider.image("fal-ai/flux/dev")
  }

  func testCreateFal_createsImageModelInstance() {
    let provider = createFal(.init(apiKey: "test-api-key"))
    let model = provider.image("fal-ai/flux/dev")
    XCTAssertTrue(model is FalImageModel)
  }
}

