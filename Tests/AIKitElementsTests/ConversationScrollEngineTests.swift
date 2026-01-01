import XCTest

@testable import AIKitElements

final class ConversationScrollEngineTests: XCTestCase {
  func testComputeIsAtLatest_returnsTrueWhenSentinelIsAtViewportBottom() {
    XCTAssertTrue(ConversationScrollEngine.computeIsAtLatest(maxY: 758, viewportHeight: 758))
  }

  func testComputeIsAtLatest_returnsTrueWhenSentinelIsAboveViewportBottom_dueToOverscrollBounce() {
    XCTAssertTrue(ConversationScrollEngine.computeIsAtLatest(maxY: 742, viewportHeight: 758))
  }

  func testComputeIsAtLatest_returnsFalseWhenSentinelIsBelowViewportBottom() {
    XCTAssertFalse(ConversationScrollEngine.computeIsAtLatest(maxY: 894, viewportHeight: 758))
  }

  func testComputeIsAtLatest_returnsFalseWhenNoSentinelMeasurement() {
    XCTAssertFalse(ConversationScrollEngine.computeIsAtLatest(maxY: -1, viewportHeight: 758))
  }

  func testComputeIsAtLatest_usesTailSentinelWhenReservedTailSpaceIsPresent() {
    let metrics = ConversationScrollEngine.LatestMetrics(
      viewportHeight: 758,
      reservedTailSpace: 1,
      bottomSentinelMaxY: 758,
      tailSentinelMaxY: 894
    )
    XCTAssertFalse(ConversationScrollEngine.computeIsAtLatest(metrics: metrics))
  }

  func testPlanForSendAnchoring_pinsModeThenScrollsToLatest() {
    let plan = ConversationScrollEngine.planForSendAnchoring(userMessageID: "u-123", hasReservedTailSpace: true)
    XCTAssertEqual(plan.steps, [
      .yield,
      .setMode(.pinUserMessageToTop(messageID: "u-123")),
      .yield,
      .scrollTo(target: .reservedTailSentinel, anchor: .bottom, animated: true),
      .yield,
      .yield,
      .reassertPinnedUserMessageIfNeeded(messageID: "u-123"),
    ])
  }
}
