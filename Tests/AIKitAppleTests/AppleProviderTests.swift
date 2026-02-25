import XCTest
import AIKitProviders
@testable import AIKitApple

final class AppleProviderTests: XCTestCase {
  func testCreateAppleBuildsLanguageModel() {
    let provider = createApple()
    let model = provider.languageModel()

    XCTAssertEqual(model.id, "apple/system")
    XCTAssertTrue(model is AppleLanguageModel)
  }

  func testCreateAppleHonorsDefaultModelSettings() {
    let provider = createApple(
      .init(
        languageModel: .init(
          modelID: "apple/custom"
        )
      )
    )
    let model = provider.languageModel()

    XCTAssertEqual(model.id, "apple/custom")
  }
}
