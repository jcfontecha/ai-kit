import XCTest
@testable import AIKitReplicate

final class ReplicateProviderTests: XCTestCase {
  func testCreateReplicate_buildsProvider() {
    let provider = createReplicate(.init(apiToken: "test-token"))
    _ = provider.image("black-forest-labs/flux-schnell")
  }

  func testCreateReplicate_buildsWithCustomBaseURL() {
    let provider = createReplicate(.init(apiToken: "test-token", baseURL: "https://custom.replicate.com/v1"))
    _ = provider.image("black-forest-labs/flux-schnell")
  }

  func testCreateReplicate_createsImageModelInstance() {
    let provider = createReplicate(.init(apiToken: "test-token"))
    let model = provider.image("black-forest-labs/flux-schnell")
    XCTAssertTrue(model is ReplicateImageModel)
  }
}

