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

  func testPlanForSendLift_scrollsToLatest_thenReasserts() {
    let plan = ConversationScrollEngine.planForSendLift(hasReservedTailSpace: true)
    XCTAssertEqual(plan.steps, [
      .yield,
      .scrollTo(target: .reservedTailSentinel, anchor: .bottom, animated: true),
      .yield,
      .yield,
      .reassertLatestIfNeeded,
    ])
  }
}
