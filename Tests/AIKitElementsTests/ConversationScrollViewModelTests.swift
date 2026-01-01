import XCTest

import AIKit
@testable import AIKitElements

@MainActor
final class ConversationScrollViewModelTests: XCTestCase {
  func testHandleOnAppear_scrollsToBottomSentinel() {
    let model = ConversationScrollViewModel()
    let steps = model.handleOnAppear(displayMessages: [])
    XCTAssertEqual(steps, [.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: false)])
    XCTAssertTrue(model.didPerformInitialScroll)
  }

  func testSendTrigger_thenMessageInsertion_producesSendAnchoringPlan() {
    let model = ConversationScrollViewModel()
    model.updateViewportHeightIfNeeded(758)

    let before: [ChatMessage] = [
      .init(id: "u-1", role: .user, parts: [.text(.init(id: "t1", text: "hi", state: .done))]),
      .init(id: "a-1", role: .assistant, parts: [.text(.init(id: "t2", text: "hello", state: .done))]),
    ]

    _ = model.handleOnAppear(displayMessages: before)
    model.handleSendTrigger(displayMessages: before)

    XCTAssertTrue(model.reservedTailBaseline > 0)
    XCTAssertTrue(model.pendingPinToTopAfterSend)

    let after: [ChatMessage] = before + [
      .init(id: "u-2", role: .user, parts: [.text(.init(id: "t3", text: "new", state: .done))]),
      .init(id: "a-2", role: .assistant, parts: [.text(.init(id: "t4", text: "", state: .streaming))]),
    ]

    let steps = model.handleMessagesCountChange(displayMessages: after)
    XCTAssertEqual(
      steps,
      ConversationScrollEngine.planForSendAnchoring(userMessageID: "u-2", hasReservedTailSpace: true).steps
    )
    XCTAssertEqual(model.pinnedUserMessageID, "u-2")
    XCTAssertEqual(model.pendingSendAnchoringMessageID, "u-2")
    XCTAssertFalse(model.pendingPinToTopAfterSend)

    // Simulate layout measurements arriving: the pinned message height and tail sentinel position.
    model.ingestMessageHeights(["u-2": 44, "a-2": 18])
    model.updateTailSentinelMaxY(1419)

    let deferredSteps = model.computeTailUpdate()
    XCTAssertEqual(
      deferredSteps,
      ConversationScrollEngine.planForSendAnchoring(userMessageID: "u-2", hasReservedTailSpace: true).steps
    )
    XCTAssertEqual(model.pendingSendAnchoringMessageID, "u-2")

    // Once we reach "latest", we clear the pending anchoring state.
    model.updateTailSentinelMaxY(742)
    XCTAssertEqual(model.computeTailUpdate(), [])
    XCTAssertEqual(model.pendingSendAnchoringMessageID, nil)
  }

  func testSendTrigger_usesCurrentViewportHeight_notMaxViewportHeightSinceAppear() {
    let model = ConversationScrollViewModel()

    let before: [ChatMessage] = [
      .init(id: "u-1", role: .user, parts: [.text(.init(id: "t1", text: "hi", state: .done))]),
      .init(id: "a-1", role: .assistant, parts: [.text(.init(id: "t2", text: "hello", state: .done))]),
    ]

    _ = model.handleOnAppear(displayMessages: before)

    // Simulate a sheet that was previously at a larger detent, then shrank.
    model.updateViewportHeightIfNeeded(920)
    model.updateViewportHeightIfNeeded(520)

    XCTAssertEqual(model.viewportHeight, 520)
    XCTAssertEqual(model.maxViewportHeightSinceAppear, 920)

    model.handleSendTrigger(displayMessages: before)

    // Reserved tail should match the current viewport (≈495 with default inset tuning), not the prior max.
    XCTAssertLessThan(model.reservedTailBaseline, 600)
  }

  func testSendTrigger_thenViewportExpands_recomputesReservedTailBaseline() {
    let model = ConversationScrollViewModel()
    model.updateBottomOverlayHeight(74)

    let before: [ChatMessage] = [
      .init(id: "u-1", role: .user, parts: [.text(.init(id: "t1", text: "hi", state: .done))]),
      .init(id: "a-1", role: .assistant, parts: [.text(.init(id: "t2", text: "hello", state: .done))]),
    ]

    // Start at a smaller viewport (e.g. sheet detent), then expand after send.
    model.updateViewportHeightIfNeeded(472)
    _ = model.handleOnAppear(displayMessages: before)
    model.handleSendTrigger(displayMessages: before)

    XCTAssertEqual(model.reservedTailBaseline, 354, accuracy: 0.5)

    model.updateViewportHeightIfNeeded(758)

    let after: [ChatMessage] = before + [
      .init(id: "u-2", role: .user, parts: [.text(.init(id: "t3", text: "new", state: .done))]),
    ]

    _ = model.handleMessagesCountChange(displayMessages: after)
    model.ingestMessageHeights(["u-2": 44])
    model.updateTailSentinelMaxY(758)
    _ = model.computeTailUpdate()

    XCTAssertEqual(model.reservedTailBaseline, 640, accuracy: 0.5)
  }


}
