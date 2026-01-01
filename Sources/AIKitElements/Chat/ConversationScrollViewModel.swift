import CoreGraphics
import Foundation
import AIKit

@MainActor
final class ConversationScrollViewModel: ObservableObject {
  // MARK: - Public state (observed by the view)

  @Published var visibleCount: Int = ConversationScrollConstants.messagePageSize
  @Published var didPerformInitialScroll: Bool = false

  @Published var isAtBottom: Bool = true
  @Published var scrollPosition: String? = ConversationScrollConstants.bottomSentinelID
  @Published var scrollMode: ScrollMode = .followBottom

  @Published var viewportHeight: CGFloat = 0
  @Published var maxViewportHeightSinceAppear: CGFloat = 0
  @Published var bottomOverlayHeight: CGFloat = 0

  @Published var reservedTailSpace: CGFloat = 0
  @Published var reservedTailBaseline: CGFloat = 0

  @Published var pendingPinToTopAfterSend: Bool = false
  @Published var pinnedUserMessageID: String?
  @Published var pendingSendAnchoringMessageID: String?

  @Published var knownDisplayMessageIDs: Set<String> = []
  @Published var preSendDisplayMessageIDs: Set<String> = []
  @Published var postSendDisplayMessageIDs: Set<String> = []

  @Published var messageHeights: [String: CGFloat] = [:]

  @Published var bottomSentinelIsVisible: Bool = true
  @Published var tailSentinelIsVisible: Bool = true
  @Published var bottomSentinelMaxY: CGFloat = -1
  @Published var tailSentinelMaxY: CGFloat = -1

  // MARK: - Internal calibration state

  private var didCalibrateReservedTailForPinnedMessageID: String?

  // MARK: - Configuration

  let extraBottomPadding: CGFloat = 0

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
    reservedTailBaseline > 0
  }

  var isAtLatestForScrollButton: Bool {
    if reservedTailSpace > 0 {
      if tailSentinelMaxY >= 0 {
        return ConversationScrollEngine.computeIsAtLatest(maxY: tailSentinelMaxY, viewportHeight: viewportHeight)
      }
      return tailSentinelIsVisible
    }
    if bottomSentinelMaxY >= 0 {
      return ConversationScrollEngine.computeIsAtLatest(maxY: bottomSentinelMaxY, viewportHeight: viewportHeight)
    }
    return bottomSentinelIsVisible
  }

  // MARK: - Lifecycle

  func handleOnAppear(displayMessages: [ChatMessage]) -> [ConversationScrollEngine.Step] {
    syncVisibleCountWithMessages(displayMessages: displayMessages)
    knownDisplayMessageIDs = Set(displayMessages.map(\.id))

    maxViewportHeightSinceAppear = 0
    scrollMode = .followBottom
    reservedTailSpace = 0
    reservedTailBaseline = 0
    didCalibrateReservedTailForPinnedMessageID = nil
    preSendDisplayMessageIDs = []
    postSendDisplayMessageIDs = []
    pinnedUserMessageID = nil
    pendingPinToTopAfterSend = false
    pendingSendAnchoringMessageID = nil
    tailSentinelIsVisible = false
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
  }

  func updateBottomOverlayHeight(_ newHeight: CGFloat) {
    bottomOverlayHeight = newHeight
  }

  func updateBottomSentinelVisibility(isVisible: Bool) {
    bottomSentinelIsVisible = isVisible
  }

  func updateTailSentinelVisibility(isVisible: Bool) {
    tailSentinelIsVisible = isVisible
  }

  func updateBottomSentinelMaxY(_ maxY: CGFloat) {
    if maxY != bottomSentinelMaxY {
      bottomSentinelMaxY = maxY
    }
    if scrollMode == .followBottom, reservedTailSpace == 0 {
      isAtBottom = ConversationScrollEngine.computeIsAtLatest(maxY: maxY, viewportHeight: viewportHeight)
    }
  }

  func updateTailSentinelMaxY(_ maxY: CGFloat) {
    if maxY != tailSentinelMaxY {
      tailSentinelMaxY = maxY
    }
    if scrollMode == .followBottom, reservedTailSpace > 0 {
      isAtBottom = ConversationScrollEngine.computeIsAtLatest(maxY: maxY, viewportHeight: viewportHeight)
    }
  }

  func ingestMessageHeights(_ heights: [String: CGFloat]) {
    guard reservedTailBaseline > 0 else { return }
    for (id, height) in heights where height.isFinite && height > 0 {
      messageHeights[id] = height
    }
  }

  // MARK: - Event handling

  func handleSendTrigger(displayMessages: [ChatMessage]) {
    pendingPinToTopAfterSend = true
    pinnedUserMessageID = nil
    pendingSendAnchoringMessageID = nil
    didCalibrateReservedTailForPinnedMessageID = nil
    preSendDisplayMessageIDs = Set(displayMessages.map(\.id))
    postSendDisplayMessageIDs = []
    messageHeights = [:]

    // Prefer the current viewport height when reserving tail space.
    //
    // In resizable presentations (e.g. sheet detents), `maxViewportHeightSinceAppear` can reflect a larger
    // detent than the user is currently at, which can cause the initial reserved tail estimate to overshoot
    // and briefly scroll the new user message off-screen.
    let effectiveViewportHeight = viewportHeight > 0 ? viewportHeight : maxViewportHeightSinceAppear
    reservedTailSpace = reserveTailSpaceForSend(viewportHeight: effectiveViewportHeight)
    reservedTailBaseline = reservedTailSpace

    // Defer actual scrolling until we see the new message inserted.
    scrollMode = .followBottom
  }

  func handleMessagesCountChange(displayMessages: [ChatMessage]) -> [ConversationScrollEngine.Step] {
    syncVisibleCountWithMessages(displayMessages: displayMessages)
    guard didPerformInitialScroll else { return [] }

    if reservedTailBaseline > 0 {
      let now = Set(displayMessages.map(\.id))
      postSendDisplayMessageIDs = now.subtracting(preSendDisplayMessageIDs)
    }

    if pendingPinToTopAfterSend, let newUserMessageID = newlyInsertedUserMessageID(displayMessages: displayMessages) {
      pinnedUserMessageID = newUserMessageID
      pendingSendAnchoringMessageID = newUserMessageID
      pendingPinToTopAfterSend = false
      knownDisplayMessageIDs = Set(displayMessages.map(\.id))
      // Defer actual programmatic scrolling until we have layout measurements (message heights / tail sentinel),
      // otherwise `ScrollViewProxy.scrollTo` can no-op if the target hasn't been laid out yet.
      return []
    }

    knownDisplayMessageIDs = Set(displayMessages.map(\.id))

    guard scrollMode == .followBottom else { return [] }
    guard isAtBottom else { return [] }
    return [
      .scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true)
    ]
  }

  func handleStatusChange(old: ChatStatus, new: ChatStatus) -> [ConversationScrollEngine.Step] {
    if old == .streaming, new != .streaming {
      // Do not clear reserved tail space on finish — keep remaining space so we don't snap.
      if reservedTailBaseline == 0, scrollMode == .followBottom {
        return [.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true)]
      }
      return []
    }
    return []
  }

  func handleBottomInsetChange() -> [ConversationScrollEngine.Step] {
    guard scrollMode == .followBottom else { return [] }
    guard isAtBottom else { return [] }
    return [.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true)]
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
    if reservedTailBaseline > 0 {
      if let pinnedUserMessageID {
        return [
          .setMode(.pinUserMessageToTop(messageID: pinnedUserMessageID)),
          .scrollTo(target: .message(pinnedUserMessageID), anchor: .top, animated: true),
        ]
      } else if reservedTailSpace > 0 {
        return [
          .setMode(.followBottom),
          .scrollTo(target: .reservedTailSentinel, anchor: .bottom, animated: true),
        ]
      }
    }

    reservedTailSpace = 0
    reservedTailBaseline = 0
    didCalibrateReservedTailForPinnedMessageID = nil
    preSendDisplayMessageIDs = []
    postSendDisplayMessageIDs = []
    pinnedUserMessageID = nil
    pendingSendAnchoringMessageID = nil
    scrollMode = .followBottom
    return [
      .setMode(.followBottom),
      .scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true),
    ]
  }

  func computeTailUpdate() -> [ConversationScrollEngine.Step] {
    guard reservedTailBaseline > 0 else { return [] }
    guard let pinnedUserMessageID else { return [] }

    var steps: [ConversationScrollEngine.Step] = []

    // After we pin the user message to the top, the initial reserved tail estimate can still overshoot,
    // leaving extra scroll range where the pinned exchange can be scrolled off-screen. Clamp the baseline
    // once we have a tail-sentinel measurement in the pinned position.
    if didCalibrateReservedTailForPinnedMessageID != pinnedUserMessageID,
       reservedTailSpace > 0,
       tailSentinelMaxY >= 0,
       viewportHeight > 0,
       scrollMode == .pinUserMessageToTop(messageID: pinnedUserMessageID) {
      let overshoot = tailSentinelMaxY - viewportHeight
      if overshoot > 2.5 {
        reservedTailBaseline = max(0, reservedTailBaseline - overshoot)
        reservedTailSpace = max(0, reservedTailSpace - overshoot)
        steps.append(.scrollTo(target: .message(pinnedUserMessageID), anchor: .top, animated: true))
      }
      didCalibrateReservedTailForPinnedMessageID = pinnedUserMessageID
    }

    if pendingSendAnchoringMessageID == pinnedUserMessageID {
      let pinnedIsLaidOut = (messageHeights[pinnedUserMessageID] != nil)
      let tailIsLaidOut = (reservedTailSpace <= 0) || (tailSentinelMaxY >= 0)
      if pinnedIsLaidOut, tailIsLaidOut, viewportHeight > 0 {
        pendingSendAnchoringMessageID = nil
        steps.append(contentsOf: ConversationScrollEngine.planForSendAnchoring(
          userMessageID: pinnedUserMessageID,
          hasReservedTailSpace: reservedTailSpace > 0
        ).steps)
      }
    }

    let responseHeight = postSendDisplayMessageIDs
      .filter { $0 != pinnedUserMessageID }
      .compactMap { messageHeights[$0] }
      .reduce(0, +)

    let remaining = max(0, reservedTailBaseline - responseHeight)

    if remaining <= 0.5 {
      // Response overflowed the reserved space: exit reserve mode and resume stick-to-bottom.
      reservedTailSpace = 0
      reservedTailBaseline = 0
      didCalibrateReservedTailForPinnedMessageID = nil
      preSendDisplayMessageIDs = []
      postSendDisplayMessageIDs = []
      self.pinnedUserMessageID = nil
      pendingSendAnchoringMessageID = nil
      scrollMode = .followBottom
      steps.append(.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true))
      return steps
    }

    reservedTailSpace = remaining
    return steps
  }

  // MARK: - Helpers

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

  private func reserveTailSpaceForSend(viewportHeight: CGFloat) -> CGFloat {
    // Keep in sync with Conversation.swift tuning.
    if viewportHeight <= 0 { return 420 }

    // We want "space for the agent" such that the newest user message can be pinned near the top of the viewport.
    // A good heuristic is: enough tail to almost fill the viewport below the last message, accounting for the composer.
    let desired = viewportHeight - (bottomInset + 24)
    let minTail: CGFloat = 320
    let maxTail: CGFloat = max(minTail, viewportHeight - (bottomInset + 8))
    return min(max(desired, minTail), maxTail)
  }
}
