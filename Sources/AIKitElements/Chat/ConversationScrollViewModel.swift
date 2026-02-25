import CoreGraphics
import Foundation
import AIKit

@MainActor
final class ConversationScrollViewModel: ObservableObject {
  // MARK: - Public state (observed by the view)

  @Published var visibleCount: Int = ConversationScrollConstants.messagePageSize

  @Published var isAtBottom: Bool = true
  @Published private(set) var isAtLatestForScrollButton: Bool = true
  @Published private(set) var isScrollInteractionDisabled: Bool = false

  @Published var bottomOverlayHeight: CGFloat = 0

  @Published var reservedTailSpace: CGFloat = 0

  @Published var pendingLiftAfterSend: Bool = false

  // MARK: - Internal state (not observed by the view)

  private(set) var didPerformInitialScroll: Bool = false

  var viewportHeight: CGFloat = 0
  var maxViewportHeightSinceAppear: CGFloat = 0

  var liftedUserMessageID: String?
  private(set) var pendingLiftAlignmentMessageID: String?

  private var knownDisplayMessageIDs: Set<String> = []
  private var preSendDisplayMessageIDs: Set<String> = []
  private var postSendDisplayMessageIDs: Set<String> = []

  private var messageHeights: [String: CGFloat] = [:]
  private var liftedUserMessageTargetMinY: CGFloat = 0

  private var bottomSentinelIsVisible: Bool = true
  private var tailSentinelIsVisible: Bool = true
  var bottomSentinelMaxY: CGFloat = -1
  var tailSentinelMaxY: CGFloat = -1

  #if DEBUG
  var debugBottomSentinelIsVisible: Bool { bottomSentinelIsVisible }
  var debugTailSentinelIsVisible: Bool { tailSentinelIsVisible }
  var debugPendingLiftAlignmentMessageID: String? { pendingLiftAlignmentMessageID }
  var debugLiftedUserMessageTargetMinY: CGFloat { liftedUserMessageTargetMinY }
  var debugKnownDisplayMessageIDsCount: Int { knownDisplayMessageIDs.count }
  var debugPreSendDisplayMessageIDsCount: Int { preSendDisplayMessageIDs.count }
  var debugPostSendDisplayMessageIDsCount: Int { postSendDisplayMessageIDs.count }
  var debugMessageHeightsCount: Int { messageHeights.count }
  #endif

  // MARK: - Configuration

  // Extra breathing room between the last message and the bottom overlay (e.g. prompt input).
  // This is intentionally a small, constant UI polish rather than another configurable knob.
  let extraBottomPadding: CGFloat = 24

  // MARK: - Derived

  var bottomInset: CGFloat {
    max(1, extraBottomPadding + bottomOverlayHeight)
  }

  /// Approximation of keyboard/safe-area intrusion, based on the scroll viewport shrinking.
  /// Used for UI heuristics (e.g. scroll-to-latest button placement) and for reserving tail space on send.
  var keyboardInsetApprox: CGFloat {
    max(0, maxViewportHeightSinceAppear - viewportHeight)
  }

  var shouldMeasureMessageHeights: Bool {
    pendingLiftAlignmentMessageID != nil || reservedTailSpace > 0
  }

  // MARK: - Lifecycle

  func handleOnAppear(displayMessages: [ChatMessage]) -> [ConversationScrollEngine.Step] {
    syncVisibleCountWithMessages(displayMessages: displayMessages)
    knownDisplayMessageIDs = Set(displayMessages.map(\.id))

    maxViewportHeightSinceAppear = max(0, viewportHeight)
    isAtBottom = true
    isAtLatestForScrollButton = true
    reservedTailSpace = 0
    isScrollInteractionDisabled = false
    preSendDisplayMessageIDs = []
    postSendDisplayMessageIDs = []
    liftedUserMessageID = nil
    pendingLiftAfterSend = false
    pendingLiftAlignmentMessageID = nil
    tailSentinelIsVisible = false
    bottomSentinelIsVisible = true
    bottomSentinelMaxY = -1
    tailSentinelMaxY = -1
    didPerformInitialScroll = true

    return [
      .scrollTo(target: .bottomSentinel, anchor: .bottom, animated: false)
    ]
  }

  // MARK: - Inputs from view

  func updateViewportHeightIfNeeded(_ newHeight: CGFloat) {
    guard newHeight.isFinite, newHeight > 0 else { return }
    if abs(viewportHeight - newHeight) > 1 {
      viewportHeight = newHeight
    }
    if newHeight > maxViewportHeightSinceAppear {
      maxViewportHeightSinceAppear = newHeight
    }
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
  }

  func updateBottomOverlayHeight(_ newHeight: CGFloat) {
    bottomOverlayHeight = newHeight
  }

  func updateBottomSentinelVisibility(isVisible: Bool) {
    bottomSentinelIsVisible = isVisible
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
  }

  func updateTailSentinelVisibility(isVisible: Bool) {
    tailSentinelIsVisible = isVisible
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
  }

  func updateBottomSentinelMaxY(_ maxY: CGFloat) {
    bottomSentinelMaxY = maxY
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
  }

  func updateTailSentinelMaxY(_ maxY: CGFloat) {
    tailSentinelMaxY = maxY
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
  }

  func ingestMessageHeights(_ heights: [String: CGFloat]) {
    guard shouldMeasureMessageHeights else { return }
    for (id, height) in heights where height.isFinite && height > 0 {
      messageHeights[id] = height
    }
  }

  func updateLiftedUserMessageTargetMinYIfNeeded(_ newValue: CGFloat) {
    guard newValue.isFinite, newValue >= 0 else { return }
    if abs(liftedUserMessageTargetMinY - newValue) > 0.75 {
      liftedUserMessageTargetMinY = newValue
    }
  }

  // MARK: - Event handling

  func handleUserScrollIntervention() {
    if pendingLiftAlignmentMessageID != nil || reservedTailSpace > 0 || pendingLiftAfterSend {
      pendingLiftAfterSend = false
      reservedTailSpace = 0
      preSendDisplayMessageIDs = []
      postSendDisplayMessageIDs = []
      liftedUserMessageID = nil
      pendingLiftAlignmentMessageID = nil
      isScrollInteractionDisabled = false
      recomputeIsAtBottomIfNeeded()
      recomputeIsAtLatestForScrollButtonIfNeeded()
    }
  }

  func releaseScrollInteractionIfNeeded() {
    if isScrollInteractionDisabled {
      isScrollInteractionDisabled = false
    }
  }

  func handleSendTrigger(displayMessages: [ChatMessage]) {
    pendingLiftAfterSend = true
    isScrollInteractionDisabled = false
    liftedUserMessageID = nil
    pendingLiftAlignmentMessageID = nil
    preSendDisplayMessageIDs = Set(displayMessages.map(\.id))
    postSendDisplayMessageIDs = []
    messageHeights = [:]
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()

    // Defer actual scrolling until we see the new message inserted.
  }

  func handleMessagesCountChange(displayMessages: [ChatMessage]) -> [ConversationScrollEngine.Step] {
    syncVisibleCountWithMessages(displayMessages: displayMessages)
    guard didPerformInitialScroll else { return [] }

    if pendingLiftAfterSend || pendingLiftAlignmentMessageID != nil || reservedTailSpace > 0 {
      let now = Set(displayMessages.map(\.id))
      postSendDisplayMessageIDs = now.subtracting(preSendDisplayMessageIDs)
    }

    if pendingLiftAfterSend, let newUserMessageID = newlyInsertedUserMessageID(displayMessages: displayMessages) {
      liftedUserMessageID = newUserMessageID
      pendingLiftAlignmentMessageID = newUserMessageID
      pendingLiftAfterSend = false
      isScrollInteractionDisabled = true
      knownDisplayMessageIDs = Set(displayMessages.map(\.id))
      // Defer scrolling until we have a measurement of the inserted message height so we can compute a precise
      // reserved tail space. (Avoids multiple "bounce" scrolls.)
      return []
    }

    knownDisplayMessageIDs = Set(displayMessages.map(\.id))

    // While reserved tail space is present, we intentionally do not auto-follow message insertions.
    // (We want the user's message to remain visually stable until reserve is exhausted.)
    if reservedTailSpace > 0 { return [] }

    guard isAtBottom else { return [] }
    return [
      .scrollTo(target: latestScrollTarget(), anchor: .bottom, animated: true)
    ]
  }

  func handleStatusChange(old: ChatStatus, new: ChatStatus) -> [ConversationScrollEngine.Step] {
    if old == .streaming, new != .streaming {
      // Do not clear reserved tail space on finish — keep remaining space so we don't snap.
      if reservedTailSpace == 0, isAtBottom {
        return [.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true)]
      }
      return []
    }
    return []
  }

  func handleBottomInsetChange() -> [ConversationScrollEngine.Step] {
    if reservedTailSpace > 0 { return [] }
    guard isAtBottom else { return [] }
    return [.scrollTo(target: latestScrollTarget(), anchor: .bottom, animated: true)]
  }

  func handleLoadOlderMessages(displayMessages: [ChatMessage], currentFirstVisibleID: String?) -> [ConversationScrollEngine.Step] {
    guard didPerformInitialScroll else { return [] }
    guard visibleCount < displayMessages.count else { return [] }

    let newCount = min(displayMessages.count, visibleCount + ConversationScrollConstants.messagePageSize)
    guard newCount != visibleCount else { return [] }
    visibleCount = newCount

    if let currentFirstVisibleID {
      return [.scrollTo(target: .message(currentFirstVisibleID), anchor: .top, animated: false)]
    }
    return []
  }

  func handleScrollToLatestButtonTapped() -> [ConversationScrollEngine.Step] {
    // Cancel any reserve-mode state and jump to the real tail.
    reservedTailSpace = 0
    preSendDisplayMessageIDs = []
    postSendDisplayMessageIDs = []
    liftedUserMessageID = nil
    pendingLiftAlignmentMessageID = nil
    isScrollInteractionDisabled = false
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
    return [
      .scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true),
    ]
  }

  func computeTailUpdate() -> [ConversationScrollEngine.Step] {
    var steps: [ConversationScrollEngine.Step] = []

    // Phase 1: Once we have the inserted user message height, compute a *precise* reserved tail and scroll
    // exactly once. (Avoids iterative "baseline calibration" and associated bounces.)
    if let liftedUserMessageID, let id = pendingLiftAlignmentMessageID, id == liftedUserMessageID {
      guard viewportHeight.isFinite, viewportHeight > 0 else { return [] }
      guard let liftedHeight = messageHeights[id] else { return [] }

      reservedTailSpace = max(0, computeReservedTailSpaceForLift(
        viewportHeight: viewportHeight,
        liftedUserMessageTargetMinY: liftedUserMessageTargetMinY,
        liftedUserMessageHeight: liftedHeight
      ))
      pendingLiftAlignmentMessageID = nil

      if reservedTailSpace > 0.5 {
        steps.append(contentsOf: ConversationScrollEngine.planForSendLift(hasReservedTailSpace: true).steps)
      } else {
        reservedTailSpace = 0
        preSendDisplayMessageIDs = []
        postSendDisplayMessageIDs = []
        self.liftedUserMessageID = nil
        pendingLiftAlignmentMessageID = nil
        isScrollInteractionDisabled = false
        steps.append(.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true))
      }

      recomputeIsAtBottomIfNeeded()
      recomputeIsAtLatestForScrollButtonIfNeeded()
      return steps
    }

    // Phase 2: While reserve is active, do not auto-scroll. Once the assistant has consumed the reserve,
    // exit reserve mode and resume bottom-follow.
    guard reservedTailSpace > 0 else { return [] }
    guard let liftedUserMessageID else { return [] }

    let responseHeight = postSendDisplayMessageIDs
      .filter { $0 != liftedUserMessageID }
      .compactMap { messageHeights[$0] }
      .reduce(0, +)

    if responseHeight >= (reservedTailSpace - 0.5) {
      reservedTailSpace = 0
      preSendDisplayMessageIDs = []
      postSendDisplayMessageIDs = []
      self.liftedUserMessageID = nil
      pendingLiftAlignmentMessageID = nil
      isScrollInteractionDisabled = false
      recomputeIsAtBottomIfNeeded()
      recomputeIsAtLatestForScrollButtonIfNeeded()
      steps.append(.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true))
      return steps
    }

    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
    return steps
  }

  // MARK: - Helpers

  func latestScrollTarget() -> ConversationScrollEngine.ScrollTarget {
    if reservedTailSpace > 0 { return .reservedTailSentinel }
    return .bottomSentinel
  }

  func shouldShowLoadMoreSentinel(displayMessages: [ChatMessage]) -> Bool {
    resolvedVisibleCount(displayMessages: displayMessages) < displayMessages.count
  }

  func visibleMessages(displayMessages: [ChatMessage]) -> ArraySlice<ChatMessage> {
    displayMessages.suffix(resolvedVisibleCount(displayMessages: displayMessages))
  }

  private func resolvedVisibleCount(displayMessages: [ChatMessage]) -> Int {
    guard displayMessages.isEmpty == false else { return 0 }
    let baseline = min(ConversationScrollConstants.messagePageSize, displayMessages.count)
    let desired = max(visibleCount, baseline)
    return min(desired, displayMessages.count)
  }

  private func syncVisibleCountWithMessages(displayMessages: [ChatMessage]) {
    guard displayMessages.isEmpty == false else {
      if visibleCount != 0 {
        visibleCount = 0
      }
      didPerformInitialScroll = false
      return
    }

    let baseline = min(ConversationScrollConstants.messagePageSize, displayMessages.count)
    if visibleCount < baseline {
      visibleCount = baseline
    } else if visibleCount > displayMessages.count {
      visibleCount = displayMessages.count
    }
  }

  private func newlyInsertedUserMessageID(displayMessages: [ChatMessage]) -> String? {
    guard displayMessages.isEmpty == false else { return nil }

    for message in displayMessages.reversed() where message.role == .user {
      if knownDisplayMessageIDs.contains(message.id) == false {
        return message.id
      }
    }

    return nil
  }
  
  private func computeReservedTailSpaceForLift(
    viewportHeight: CGFloat,
    liftedUserMessageTargetMinY: CGFloat,
    liftedUserMessageHeight: CGFloat
  ) -> CGFloat {
    guard viewportHeight.isFinite, viewportHeight > 0 else { return 0 }
    guard liftedUserMessageHeight.isFinite, liftedUserMessageHeight > 0 else { return 0 }
    let targetMinY = max(0, liftedUserMessageTargetMinY)

    // Layout model when scrolling to the reserved-tail sentinel (1pt) anchored to viewport bottom:
    // [user message][bottom inset (incl. 1pt bottom sentinel)][reservedTailSpace][1pt reserved-tail sentinel]
    //
    // We want `userMessage.minY == targetMinY`.
    //
    // distance(userTop -> reservedTailSentinelBottom) =
    //   userMessageHeight + bottomInset + 1 + reservedTailSpace + 1
    //
    // So: reservedTailSpace = viewportHeight - targetMinY - userMessageHeight - bottomInset - 2
    return viewportHeight - targetMinY - liftedUserMessageHeight - bottomInset - 2
  }

  private func recomputeIsAtBottomIfNeeded() {
    let newValue: Bool
    if reservedTailSpace > 0 {
      if tailSentinelMaxY >= 0 {
        newValue = ConversationScrollEngine.computeIsAtLatest(maxY: tailSentinelMaxY, viewportHeight: viewportHeight)
      } else {
        newValue = tailSentinelIsVisible
      }
    } else {
      if bottomSentinelMaxY >= 0 {
        newValue = ConversationScrollEngine.computeIsAtLatest(maxY: bottomSentinelMaxY, viewportHeight: viewportHeight)
      } else {
        newValue = bottomSentinelIsVisible
      }
    }

    if newValue != isAtBottom {
      isAtBottom = newValue
    }
  }

  private func recomputeIsAtLatestForScrollButtonIfNeeded() {
    let newValue: Bool
    if reservedTailSpace > 0 {
      if tailSentinelMaxY >= 0 {
        newValue = ConversationScrollEngine.computeIsAtLatest(maxY: tailSentinelMaxY, viewportHeight: viewportHeight)
      } else {
        newValue = tailSentinelIsVisible
      }
    } else {
      if bottomSentinelMaxY >= 0 {
        newValue = ConversationScrollEngine.computeIsAtLatest(maxY: bottomSentinelMaxY, viewportHeight: viewportHeight)
      } else {
        newValue = bottomSentinelIsVisible
      }
    }

    if newValue != isAtLatestForScrollButton {
      isAtLatestForScrollButton = newValue
    }
  }
}
