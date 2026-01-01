import CoreGraphics
import Foundation
import AIKit

@MainActor
final class ConversationScrollViewModel: ObservableObject {
  // MARK: - Public state (observed by the view)

  @Published var visibleCount: Int = ConversationScrollConstants.messagePageSize

  @Published var isAtBottom: Bool = true
  @Published private(set) var isAtLatestForScrollButton: Bool = true
  @Published var scrollPosition: String? = ConversationScrollConstants.bottomSentinelID
  @Published var scrollMode: ScrollMode = .followBottom

  @Published var bottomOverlayHeight: CGFloat = 0

  @Published var reservedTailSpace: CGFloat = 0
  @Published var reservedTailBaseline: CGFloat = 0

  @Published var pendingPinToTopAfterSend: Bool = false

  // MARK: - Internal state (not observed by the view)

  private(set) var didPerformInitialScroll: Bool = false

  var viewportHeight: CGFloat = 0
  var maxViewportHeightSinceAppear: CGFloat = 0

  var keyboardHeight: CGFloat = 0
  private var sendTriggerViewportHeight: CGFloat = 0

  var pinnedUserMessageID: String?
  private(set) var pendingSendAnchoringMessageID: String?

  private var knownDisplayMessageIDs: Set<String> = []
  private var preSendDisplayMessageIDs: Set<String> = []
  private var postSendDisplayMessageIDs: Set<String> = []

  private var messageHeights: [String: CGFloat] = [:]

  private var bottomSentinelIsVisible: Bool = true
  private var tailSentinelIsVisible: Bool = true
  var bottomSentinelMaxY: CGFloat = -1
  var tailSentinelMaxY: CGFloat = -1

  #if DEBUG
  var debugBottomSentinelIsVisible: Bool { bottomSentinelIsVisible }
  var debugTailSentinelIsVisible: Bool { tailSentinelIsVisible }
  var debugPendingSendAnchoringMessageID: String? { pendingSendAnchoringMessageID }
  var debugKnownDisplayMessageIDsCount: Int { knownDisplayMessageIDs.count }
  var debugPreSendDisplayMessageIDsCount: Int { preSendDisplayMessageIDs.count }
  var debugPostSendDisplayMessageIDsCount: Int { postSendDisplayMessageIDs.count }
  var debugMessageHeightsCount: Int { messageHeights.count }
  #endif

  // MARK: - Internal calibration state

  private var didCalibrateReservedTailForPinnedMessageID: String?
  private var sendAnchoringAttemptCount: Int = 0

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

  // MARK: - Lifecycle

  func handleOnAppear(displayMessages: [ChatMessage]) -> [ConversationScrollEngine.Step] {
    syncVisibleCountWithMessages(displayMessages: displayMessages)
    knownDisplayMessageIDs = Set(displayMessages.map(\.id))

    maxViewportHeightSinceAppear = max(0, viewportHeight)
    scrollMode = .followBottom
    isAtBottom = true
    isAtLatestForScrollButton = true
    reservedTailSpace = 0
    reservedTailBaseline = 0
    didCalibrateReservedTailForPinnedMessageID = nil
    sendAnchoringAttemptCount = 0
    preSendDisplayMessageIDs = []
    postSendDisplayMessageIDs = []
    pinnedUserMessageID = nil
    pendingPinToTopAfterSend = false
    pendingSendAnchoringMessageID = nil
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

  func updateKeyboardHeightIfNeeded(_ newHeight: CGFloat) {
    guard newHeight.isFinite, newHeight >= 0 else { return }
    if abs(keyboardHeight - newHeight) > 1 {
      keyboardHeight = newHeight
    }
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
    sendAnchoringAttemptCount = 0
    preSendDisplayMessageIDs = Set(displayMessages.map(\.id))
    postSendDisplayMessageIDs = []
    messageHeights = [:]

    sendTriggerViewportHeight = viewportHeight

    // Reserve tail space using a "keyboard-free" viewport estimate for the *current* presentation size.
    //
    // `keyboardHeight` comes from platform keyboard notifications and avoids relying on
    // `maxViewportHeightSinceAppear` (which can include prior sheet detents).
    let effectiveViewportHeight: CGFloat
    if viewportHeight > 0 {
      let keyboardAdjusted = viewportHeight + keyboardHeight
      if maxViewportHeightSinceAppear > 0 {
        effectiveViewportHeight = min(keyboardAdjusted, maxViewportHeightSinceAppear)
      } else {
        effectiveViewportHeight = keyboardAdjusted
      }
    } else {
      effectiveViewportHeight = maxViewportHeightSinceAppear
    }
    reservedTailSpace = reserveTailSpaceForSend(viewportHeight: effectiveViewportHeight)
    reservedTailBaseline = reservedTailSpace
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()

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
      sendAnchoringAttemptCount = 0
      // Scroll immediately so the user sees their sent message, even if we need to reassert later.
      return ConversationScrollEngine.planForSendAnchoring(
        userMessageID: newUserMessageID,
        hasReservedTailSpace: reservedTailSpace > 0
      ).steps
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
          .scrollTo(target: .reservedTailSentinel, anchor: .bottom, animated: true),
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
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
    return [
      .setMode(.followBottom),
      .scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true),
    ]
  }

  func computeTailUpdate() -> [ConversationScrollEngine.Step] {
    guard reservedTailBaseline > 0 else { return [] }
    guard let pinnedUserMessageID else { return [] }

    var steps: [ConversationScrollEngine.Step] = []

    let responseHeight = postSendDisplayMessageIDs
      .filter { $0 != pinnedUserMessageID }
      .compactMap { messageHeights[$0] }
      .reduce(0, +)

    // If the viewport (or composer) size changed after the send trigger was recorded, the initial reserved tail
    // estimate can become too small to actually pin the user message near the top. Expand the baseline
    // opportunistically, including after keyboard dismissal (viewport expands) even if some response height is
    // already present.
    let effectiveViewportHeight = viewportHeight > 0 ? viewportHeight : maxViewportHeightSinceAppear
    let desiredBaseline = reserveTailSpaceForSend(viewportHeight: effectiveViewportHeight)
    let viewportExpandedAfterSend = (sendTriggerViewportHeight > 0) && ((viewportHeight - sendTriggerViewportHeight) > 60)
    if desiredBaseline > (reservedTailBaseline + 2.5),
       (responseHeight <= 0.5 || viewportExpandedAfterSend) {
      reservedTailBaseline = desiredBaseline
      didCalibrateReservedTailForPinnedMessageID = nil
      // Re-assert latest positioning once the scroll range expands.
      steps.append(.scrollTo(target: .reservedTailSentinel, anchor: .bottom, animated: true))
    }

    if pendingSendAnchoringMessageID == pinnedUserMessageID {
      let pinnedIsLaidOut = (messageHeights[pinnedUserMessageID] != nil)
      let tailIsLaidOut = (reservedTailSpace <= 0) || (tailSentinelMaxY >= 0)
      if pinnedIsLaidOut, tailIsLaidOut, viewportHeight > 0 {
        let isAtLatest: Bool
        if reservedTailSpace > 0 {
          isAtLatest = ConversationScrollEngine.computeIsAtLatest(maxY: tailSentinelMaxY, viewportHeight: viewportHeight)
        } else {
          isAtLatest = ConversationScrollEngine.computeIsAtLatest(maxY: bottomSentinelMaxY, viewportHeight: viewportHeight)
        }

        if isAtLatest {
          pendingSendAnchoringMessageID = nil
          sendAnchoringAttemptCount = 0
        } else if sendAnchoringAttemptCount < 6 {
          sendAnchoringAttemptCount += 1
          steps.append(contentsOf: ConversationScrollEngine.planForSendAnchoring(
            userMessageID: pinnedUserMessageID,
            hasReservedTailSpace: reservedTailSpace > 0
          ).steps)
        } else {
          // Give up rather than looping forever; user can tap "scroll to latest".
          pendingSendAnchoringMessageID = nil
          sendAnchoringAttemptCount = 0
        }
      }
    }

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
      recomputeIsAtBottomIfNeeded()
      recomputeIsAtLatestForScrollButtonIfNeeded()
      steps.append(.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true))
      return steps
    }

    reservedTailSpace = remaining

    // NOTE: Do not attempt to clamp `reservedTailBaseline` based on tail-sentinel geometry here.
    // Those measurements depend on transient scroll state and can collapse the reserved tail space,
    // preventing the pinned message from reaching the top.
    recomputeIsAtBottomIfNeeded()
    recomputeIsAtLatestForScrollButtonIfNeeded()
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

    // Extra top breathing room: reduces the reserved tail so the pinned user message lands slightly lower.
    let pinnedTopOffset: CGFloat = 20

    // We want "space for the agent" such that the newest user message can be pinned near the top of the viewport.
    // A good heuristic is: enough tail to almost fill the viewport below the last message, accounting for the composer.
    let desired = viewportHeight - (bottomInset + 24 + pinnedTopOffset)
    let minTail: CGFloat = 320
    let maxTail: CGFloat = max(minTail, viewportHeight - (bottomInset + 8 + pinnedTopOffset))
    return min(max(desired, minTail), maxTail)
  }

  private func recomputeIsAtBottomIfNeeded() {
    guard scrollMode == .followBottom else {
      if isAtBottom != false { isAtBottom = false }
      return
    }

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
