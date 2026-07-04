import CoreGraphics
import Testing

@testable import AIKitElements

private typealias K = ConversationScrollerConstants

private func geometry(
  offsetY: CGFloat = 0,
  contentHeight: CGFloat = 0,
  containerHeight: CGFloat = 600,
  topInset: CGFloat = 0,
  bottomInset: CGFloat = 24
) -> ConversationScrollGeometry {
  ConversationScrollGeometry(
    offsetY: offsetY,
    contentHeight: contentHeight,
    containerHeight: containerHeight,
    topInset: topInset,
    bottomInset: bottomInset
  )
}

private func row(_ id: String, anchor: Bool = false) -> ConversationScrollRow {
  ConversationScrollRow(id: id, isAnchor: anchor)
}

// Core resting at the end of a simple transcript: marker at 1000, viewport 600,
// no insets, end rest offset 400.
private func coreAtEnd() -> ConversationScrollerCore {
  var core = ConversationScrollerCore()
  core.endMarkerContentMaxY = 1000
  core.geometry = geometry(offsetY: 400, contentHeight: 1000)
  core.mode = .followingBottom
  return core
}

// appear [a1] at rest, then append the anchor row u1.
// em=200, rowGap 12, no padding: estRowTop = 212, target = 212 − 64 = 148,
// spacer = 148 + 600 − 200 = 548.
private func anchoredCore() -> ConversationScrollerCore {
  var core = ConversationScrollerCore()
  _ = core.handleAppear(rows: [row("a1")])
  core.endMarkerContentMaxY = 200
  core.geometry = geometry(offsetY: 0, contentHeight: 224)
  core.mode = .followingBottom
  let command = core.handleContentChange(rows: [row("a1"), row("u1", anchor: true)], rowGap: 12, bottomContentPadding: 0)
  precondition(command == .toOffset(y: 148))
  return core
}

// MARK: - At-end calibration

@Test func atEnd_isZeroAtPinRestWithInsets() {
  // Real trace from the push-nav demo: em=927 offset=151 tI=116 vH=660.
  var core = ConversationScrollerCore()
  core.endMarkerContentMaxY = 927
  core.geometry = geometry(offsetY: 151, contentHeight: 927, containerHeight: 660, topInset: 116, bottomInset: 98)
  #expect(core.distanceFromEnd == 0)
  #expect(core.isAtEnd)
}

@Test func atEnd_isTrueDuringRubberBandPastEnd() {
  var core = coreAtEnd()
  core.geometry.offsetY = 430
  #expect(core.distanceFromEnd < 0)
  #expect(core.isAtEnd)
}

@Test func atEnd_isFalseWithContentBelow() {
  var core = coreAtEnd()
  core.geometry.offsetY = 200
  #expect(core.distanceFromEnd == 200)
  #expect(core.isAtEnd == false)
}

@Test func atEnd_thresholdBoundary() {
  var core = coreAtEnd()
  core.geometry.offsetY = 400 - K.scrollEdgeThreshold
  #expect(core.isAtEnd)
  core.geometry.offsetY -= 1
  #expect(core.isAtEnd == false)
}

@Test func atEnd_ignoresSpacerSoAnchoredShortTurnCountsAtEnd() {
  // The marker sits before the tail spacer, so a freshly anchored short turn
  // (viewport extending into the spacer) still measures at/past the end.
  var core = ConversationScrollerCore()
  core.endMarkerContentMaxY = 600
  core.spacerHeight = 500
  core.geometry = geometry(offsetY: 100, contentHeight: 1100)
  #expect(core.distanceFromEnd == -100)
  #expect(core.isAtEnd)
}

// MARK: - Appear

@Test func appear_withRowsPinsEndAndMarksAnchorsHandled() {
  var core = ConversationScrollerCore()
  #expect(core.handleAppear(rows: [row("u1", anchor: true), row("a1")]) == .toEnd(animated: false))
  #expect(core.mode == .followingBottom)
  // The pre-existing anchor never re-anchors.
  core.endMarkerContentMaxY = 300
  core.geometry = geometry(offsetY: 0, contentHeight: 300)
  let next = core.handleContentChange(rows: [row("u1", anchor: true), row("a1")], rowGap: 12, bottomContentPadding: 0)
  #expect(next == nil)
  #expect(core.mode == .followingBottom)
}

@Test func appear_emptyEmitsNothing() {
  var core = ConversationScrollerCore()
  #expect(core.handleAppear(rows: []) == nil)
}

// MARK: - Release / re-pin / re-arm

@Test func release_onPureOffsetFrameOffEnd() {
  var core = coreAtEnd()
  _ = core.handleGeometryChange(geometry(offsetY: 200, contentHeight: 1000), totalDisplayCount: 0)
  #expect(core.mode == .freeScrolling)
}

@Test func churn_offTheEndRepinsInsteadOfReleasing() {
  // Keyboard churn from the real trace: container shrinks 660 -> 616 while
  // following; the frame is off the end but layout changed, so it re-pins.
  var core = ConversationScrollerCore()
  core.endMarkerContentMaxY = 927
  core.geometry = geometry(offsetY: 151, contentHeight: 927, containerHeight: 660, topInset: 116, bottomInset: 98)
  core.mode = .followingBottom
  let command = core.handleGeometryChange(
    geometry(offsetY: 151, contentHeight: 927, containerHeight: 616, topInset: 116, bottomInset: 142),
    totalDisplayCount: 0
  )
  #expect(command == .toEnd(animated: false))
  #expect(core.mode == .followingBottom)
}

@Test func churn_atTheEndEmitsNothing() {
  // A growth frame the native size-change anchor already pinned in-pass
  // (marker already moved with it).
  var core = coreAtEnd()
  core.endMarkerContentMaxY = 1100
  let command = core.handleGeometryChange(geometry(offsetY: 500, contentHeight: 1100), totalDisplayCount: 0)
  #expect(command == nil)
  #expect(core.mode == .followingBottom)
}

@Test func rearm_atRealEndDropsSpacerAndFollows() {
  var core = coreAtEnd()
  core.mode = .freeScrolling
  core.spacerHeight = 500
  _ = core.handleGeometryChange(geometry(offsetY: 400, contentHeight: 1500), totalDisplayCount: 0)
  #expect(core.mode == .followingBottom)
  #expect(core.spacerHeight == 0)
}

@Test func rearm_doesNotFireDeepInsideSpacer() {
  // A grabbed anchored turn rests past the marker (inside the tail spacer).
  // isAtEnd is true there, but re-arming would drop the spacer and clamp the
  // offset against the reader's drag — must stay released.
  var core = coreAtEnd()
  core.mode = .freeScrolling
  core.spacerHeight = 500
  _ = core.handleGeometryChange(geometry(offsetY: 700, contentHeight: 1500), totalDisplayCount: 0)
  #expect(core.distanceFromEnd == -300)
  #expect(core.mode == .freeScrolling)
  #expect(core.spacerHeight == 500)
}

// MARK: - End marker events

@Test func marker_pinsWhileFollowingOffEnd() {
  var core = coreAtEnd()
  // Content grew below the fold: marker moves, geometry offset unchanged.
  let command = core.handleEndMarkerChange(contentMaxY: 1200)
  #expect(command == .toEnd(animated: false))
  #expect(core.mode == .followingBottom)
}

@Test func marker_atEndEmitsNothing() {
  var core = coreAtEnd()
  #expect(core.handleEndMarkerChange(contentMaxY: 1005) == nil)
}

@Test func marker_updatesSpacerWhileAnchored() {
  var core = anchoredCore()
  // The reply streams in below the anchored turn: marker 200 -> 400 shrinks
  // the spacer 1:1 (548 -> 348) with no command — zero movement.
  let command = core.handleEndMarkerChange(contentMaxY: 400)
  #expect(command == nil)
  #expect(core.spacerHeight == 348)
  #expect(core.mode == .anchoredToMessage)
}

// MARK: - Anchoring

@Test func anchor_appendedUserTurnPlacesTargetAndSpacer() {
  let core = anchoredCore()
  #expect(core.mode == .anchoredToMessage)
  #expect(core.anchoredRowID == "u1")
  #expect(core.spacerHeight == 548)
}

@Test func anchor_estimateAccountsForBottomContentPaddingAndTopInset() {
  var core = ConversationScrollerCore()
  _ = core.handleAppear(rows: [row("a1")])
  core.endMarkerContentMaxY = 200
  core.geometry = geometry(offsetY: 0, contentHeight: 224, topInset: 70)
  let command = core.handleContentChange(rows: [row("a1"), row("u1", anchor: true)], rowGap: 12, bottomContentPadding: 16)
  // estRowTop = 200 − 16 + 12 = 196; target = 196 − 70 − 64 = 62.
  #expect(command == .toOffset(y: 62))
}

@Test func anchor_rowFrameCorrectsPlacement() {
  var core = anchoredCore()
  core.geometry.offsetY = 148 // placement landed
  // The row really laid out 26pt below the reading line (peek = 64).
  let command = core.handleAnchorRowFrame(viewportTop: 90)
  #expect(command == .toOffset(y: 174))
  // spacer = 174 + 600 − 200 = 574.
  #expect(core.spacerHeight == 574)
}

@Test func anchor_rowFrameIgnoresSubEpsilonDrift() {
  var core = anchoredCore()
  core.geometry.offsetY = 148
  #expect(core.handleAnchorRowFrame(viewportTop: 64.2) == nil)
}

@Test func anchor_spacerNeverNegativeAndModePersistsAfterExhaustion() {
  var core = anchoredCore()
  // The reply far overruns the spacer; anchoring stays engaged (new content
  // arrives offscreen) and the spacer clamps at zero.
  _ = core.handleEndMarkerChange(contentMaxY: 2000)
  #expect(core.spacerHeight == 0)
  #expect(core.mode == .anchoredToMessage)
  let command = core.handleGeometryChange(geometry(offsetY: 148, contentHeight: 2000), totalDisplayCount: 0)
  #expect(command == nil)
  #expect(core.mode == .anchoredToMessage)
}

@Test func anchor_multipleNewAnchorsWhileFollowingKeepsFollowing() {
  var core = ConversationScrollerCore()
  _ = core.handleAppear(rows: [row("a1")])
  core.endMarkerContentMaxY = 200
  core.geometry = geometry(offsetY: 0, contentHeight: 224)
  let command = core.handleContentChange(
    rows: [row("a1"), row("u1", anchor: true), row("u2", anchor: true)],
    rowGap: 12,
    bottomContentPadding: 0
  )
  #expect(command == nil)
  #expect(core.mode == .followingBottom)
  #expect(core.anchoredRowID == nil)
  // Batch members are marked handled: a later same-count update cannot anchor.
  let next = core.handleContentChange(
    rows: [row("a1"), row("u1", anchor: true), row("u2", anchor: true)],
    rowGap: 12,
    bottomContentPadding: 0
  )
  #expect(next == nil)
}

@Test func anchor_replacedMessageAnchorsExactlyOnce() {
  var core = ConversationScrollerCore()
  _ = core.handleAppear(rows: [row("u1", anchor: true), row("a1")])
  core.endMarkerContentMaxY = 300
  core.geometry = geometry(offsetY: 0, contentHeight: 300)
  // Same count, new id (edited/replaced user message).
  let first = core.handleContentChange(rows: [row("u2", anchor: true), row("a1")], rowGap: 12, bottomContentPadding: 0)
  #expect(core.mode == .anchoredToMessage)
  #expect(core.anchoredRowID == "u2")
  if case .toOffset = first {} else { Issue.record("expected a toOffset command") }
  let second = core.handleContentChange(rows: [row("u2", anchor: true), row("a1")], rowGap: 12, bottomContentPadding: 0)
  #expect(second == nil)
}

// MARK: - First content

@Test func firstContent_armsFollowingAndMarksAnchorsHandled() {
  var core = ConversationScrollerCore()
  let command = core.handleContentChange(rows: [row("u1", anchor: true), row("a1")], rowGap: 12, bottomContentPadding: 0)
  #expect(command == nil)
  #expect(core.mode == .followingBottom)
  let next = core.handleContentChange(rows: [row("u1", anchor: true), row("a1")], rowGap: 12, bottomContentPadding: 0)
  #expect(next == nil)
}

// MARK: - Pagination

@Test func pagination_bumpsOnceNearTopUntilRowsLand() {
  var core = ConversationScrollerCore()
  // Window shows the last 60 of 100 messages.
  _ = core.handleAppear(rows: (40..<100).map { row("m\($0)") })
  core.endMarkerContentMaxY = 5000
  core.geometry = geometry(offsetY: 110, contentHeight: 5000)
  core.mode = .freeScrolling
  _ = core.handleGeometryChange(geometry(offsetY: 100, contentHeight: 5000), totalDisplayCount: 100)
  #expect(core.visibleCount == K.messagePageSize * 2)
  // A second near-top frame BEFORE the new rows land must not bump again.
  _ = core.handleGeometryChange(geometry(offsetY: 90, contentHeight: 5000), totalDisplayCount: 100)
  #expect(core.visibleCount == K.messagePageSize * 2)
}

@Test func pagination_prependRepinsPreviousFirstRowTop() {
  var core = ConversationScrollerCore()
  _ = core.handleAppear(rows: (40..<100).map { row("m\($0)") })
  core.endMarkerContentMaxY = 5000
  core.geometry = geometry(offsetY: 100, contentHeight: 5000)
  core.mode = .freeScrolling
  _ = core.handleGeometryChange(geometry(offsetY: 90, contentHeight: 5000), totalDisplayCount: 100)
  // The older page lands: the prior first row is now deeper in the list.
  let command = core.handleContentChange(
    rows: (0..<100).map { row("m\($0)") },
    rowGap: 12,
    bottomContentPadding: 0
  )
  #expect(command == .toRowTop(id: "m40"))
}

// MARK: - User intent / jump

@Test func userIntent_releasesModeButLeavesSpacer() {
  var core = anchoredCore()
  core.userScrollIntent()
  #expect(core.mode == .freeScrolling)
  #expect(core.anchoredRowID == nil)
  #expect(core.spacerHeight == 548)
}

@Test func scrollToEndRequested_clearsSpacerAndSettles() {
  var core = anchoredCore()
  let command = core.scrollToEndRequested()
  #expect(command == .toEnd(animated: true))
  #expect(core.mode == .settlingJump)
  #expect(core.spacerHeight == 0)
  #expect(core.anchoredRowID == nil)
}

@Test func settlingJump_settlesGeometricallyAtEnd() {
  var core = coreAtEnd()
  core.mode = .settlingJump
  core.geometry.offsetY = 200
  // Mid-animation, not at end: keeps settling.
  _ = core.handleGeometryChange(geometry(offsetY: 300, contentHeight: 1000), totalDisplayCount: 0)
  #expect(core.mode == .settlingJump)
  // Arrival at the end settles into following even if no .idle phase fires.
  _ = core.handleGeometryChange(geometry(offsetY: 400, contentHeight: 1000), totalDisplayCount: 0)
  #expect(core.mode == .followingBottom)
}

// MARK: - Scroll phases

@Test func phase_interactingReleasesAllModes() {
  var core = coreAtEnd()
  _ = core.handleScrollPhase(.interacting)
  #expect(core.mode == .freeScrolling)

  var anchored = anchoredCore()
  _ = anchored.handleScrollPhase(.interacting)
  #expect(anchored.mode == .freeScrolling)
  #expect(anchored.anchoredRowID == nil)
}

@Test func phase_trackingAnimatingDeceleratingDoNotRelease() {
  var core = anchoredCore()
  #expect(core.handleScrollPhase(.tracking) == nil)
  #expect(core.handleScrollPhase(.animating) == nil)
  #expect(core.handleScrollPhase(.decelerating) == nil)
  #expect(core.mode == .anchoredToMessage)
}

@Test func phase_idleSettlesJumpIntoFollowing() {
  var core = coreAtEnd()
  core.mode = .settlingJump
  #expect(core.handleScrollPhase(.idle) == nil)
  #expect(core.mode == .followingBottom)
}

@Test func phase_idleReassertsJumpThatSettledShort() {
  var core = coreAtEnd()
  core.mode = .settlingJump
  // Lazy row estimates shifted the content mid-flight; the jump landed short.
  core.geometry.offsetY = 200
  #expect(core.handleScrollPhase(.idle) == .toEnd(animated: true))
  #expect(core.mode == .settlingJump)
}

@Test func phase_idleRearmsAtRealEnd() {
  var core = coreAtEnd()
  core.mode = .freeScrolling
  core.spacerHeight = 200
  #expect(core.handleScrollPhase(.idle) == nil)
  #expect(core.mode == .followingBottom)
  #expect(core.spacerHeight == 0)
}
