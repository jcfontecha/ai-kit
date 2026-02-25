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

  func testSendTrigger_thenMessageInsertion_thenHeightMeasurement_producesLiftPlan_withComputedReservedTailSpace() {
    let model = ConversationScrollViewModel()
    model.updateLiftedUserMessageTargetMinYIfNeeded(64)
    model.updateViewportHeightIfNeeded(758)

    let before: [ChatMessage] = [
      .init(id: "u-1", role: .user, parts: [.text(.init(id: "t1", text: "hi", state: .done))]),
      .init(id: "a-1", role: .assistant, parts: [.text(.init(id: "t2", text: "hello", state: .done))]),
    ]

    _ = model.handleOnAppear(displayMessages: before)
    model.handleSendTrigger(displayMessages: before)

    XCTAssertTrue(model.pendingLiftAfterSend)

    let after: [ChatMessage] = before + [
      .init(id: "u-2", role: .user, parts: [.text(.init(id: "t3", text: "new", state: .done))]),
      .init(id: "a-2", role: .assistant, parts: [.text(.init(id: "t4", text: "", state: .streaming))]),
    ]

    XCTAssertEqual(model.handleMessagesCountChange(displayMessages: after), [])
    XCTAssertEqual(model.liftedUserMessageID, "u-2")
    XCTAssertEqual(model.pendingLiftAlignmentMessageID, "u-2")
    XCTAssertFalse(model.pendingLiftAfterSend)
    XCTAssertTrue(model.isScrollInteractionDisabled)

    // Simulate layout measurement arriving for the inserted user message.
    model.ingestMessageHeights(["u-2": 44])
    XCTAssertEqual(
      model.computeTailUpdate(),
      ConversationScrollEngine.planForSendLift(hasReservedTailSpace: true).steps
    )

    // reservedTailSpace = 758 - 64 - 44 - bottomInset(=24) - 2 = 624
    XCTAssertEqual(model.reservedTailSpace, 624, accuracy: 0.5)
    XCTAssertEqual(model.pendingLiftAlignmentMessageID, nil)
  }

  func testComputeTailUpdate_doesNotChangeReservedTailSpaceWhileAssistantGrows() {
    let model = ConversationScrollViewModel()
    model.updateLiftedUserMessageTargetMinYIfNeeded(64)
    model.updateViewportHeightIfNeeded(758)

    let before: [ChatMessage] = [
      .init(id: "u-1", role: .user, parts: [.text(.init(id: "t1", text: "hi", state: .done))]),
      .init(id: "a-1", role: .assistant, parts: [.text(.init(id: "t2", text: "hello", state: .done))]),
    ]

    _ = model.handleOnAppear(displayMessages: before)
    model.handleSendTrigger(displayMessages: before)

    let after: [ChatMessage] = before + [
      .init(id: "u-2", role: .user, parts: [.text(.init(id: "t3", text: "new", state: .done))]),
      .init(id: "a-2", role: .assistant, parts: [.text(.init(id: "t4", text: "", state: .streaming))]),
    ]

    _ = model.handleMessagesCountChange(displayMessages: after)
    model.ingestMessageHeights(["u-2": 44])
    _ = model.computeTailUpdate()

    let baseline = model.reservedTailSpace
    XCTAssertTrue(baseline > 0)

    model.ingestMessageHeights(["a-2": 18])
    XCTAssertEqual(model.computeTailUpdate(), [])
    XCTAssertEqual(model.reservedTailSpace, baseline, accuracy: 0.5)
  }

  func testComputeTailUpdate_exitsReserveMode_whenAssistantConsumesReserve() {
    let model = ConversationScrollViewModel()
    model.updateLiftedUserMessageTargetMinYIfNeeded(64)
    model.updateViewportHeightIfNeeded(240)

    let before: [ChatMessage] = [
      .init(id: "u-1", role: .user, parts: [.text(.init(id: "t1", text: "hi", state: .done))]),
    ]

    _ = model.handleOnAppear(displayMessages: before)
    model.handleSendTrigger(displayMessages: before)

    let after: [ChatMessage] = before + [
      .init(id: "u-2", role: .user, parts: [.text(.init(id: "t2", text: "new", state: .done))]),
      .init(id: "a-1", role: .assistant, parts: [.text(.init(id: "t3", text: "x", state: .streaming))]),
    ]

    _ = model.handleMessagesCountChange(displayMessages: after)
    model.ingestMessageHeights(["u-2": 44])
    _ = model.computeTailUpdate()

    let baseline = model.reservedTailSpace
    XCTAssertTrue(baseline > 0)

    model.ingestMessageHeights(["a-1": baseline + 10])
    XCTAssertEqual(
      model.computeTailUpdate(),
      [.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true)]
    )
    XCTAssertEqual(model.reservedTailSpace, 0)
    XCTAssertEqual(model.liftedUserMessageID, nil)
  }
}
