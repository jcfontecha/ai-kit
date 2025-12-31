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
  @Published var bottomOverlayHeight: CGFloat = 0

  @Published var reservedTailSpace: CGFloat = 0
  @Published var reservedTailBaseline: CGFloat = 0

  @Published var pendingPinToTopAfterSend: Bool = false
  @Published var pinnedUserMessageID: String?

  @Published var knownDisplayMessageIDs: Set<String> = []
  @Published var preSendDisplayMessageIDs: Set<String> = []
  @Published var postSendDisplayMessageIDs: Set<String> = []

  @Published var messageHeights: [String: CGFloat] = [:]

  @Published var bottomSentinelIsVisible: Bool = true
  @Published var tailSentinelIsVisible: Bool = true
  @Published var bottomSentinelMaxY: CGFloat = -1
  @Published var tailSentinelMaxY: CGFloat = -1

  // MARK: - Configuration

  let extraBottomPadding: CGFloat = 0

  // MARK: - Derived

  var bottomInset: CGFloat {
    max(1, extraBottomPadding + bottomOverlayHeight)
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

    scrollMode = .followBottom
    reservedTailSpace = 0
    reservedTailBaseline = 0
    preSendDisplayMessageIDs = []
    postSendDisplayMessageIDs = []
    pinnedUserMessageID = nil
    pendingPinToTopAfterSend = false
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
    preSendDisplayMessageIDs = Set(displayMessages.map(\.id))
    postSendDisplayMessageIDs = []
    messageHeights = [:]

    reservedTailSpace = reserveTailSpaceForSend(viewportHeight: viewportHeight)
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
      pendingPinToTopAfterSend = false
      knownDisplayMessageIDs = Set(displayMessages.map(\.id))
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
    preSendDisplayMessageIDs = []
    postSendDisplayMessageIDs = []
    pinnedUserMessageID = nil
    scrollMode = .followBottom
    return [
      .setMode(.followBottom),
      .scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true),
    ]
  }

  func computeTailUpdate() -> [ConversationScrollEngine.Step] {
    guard reservedTailBaseline > 0 else { return [] }
    guard let pinnedUserMessageID else { return [] }

    let responseHeight = postSendDisplayMessageIDs
      .filter { $0 != pinnedUserMessageID }
      .compactMap { messageHeights[$0] }
      .reduce(0, +)

    let remaining = max(0, reservedTailBaseline - responseHeight)

    if remaining <= 0.5 {
      // Response overflowed the reserved space: exit reserve mode and resume stick-to-bottom.
      reservedTailSpace = 0
      reservedTailBaseline = 0
      preSendDisplayMessageIDs = []
      postSendDisplayMessageIDs = []
      self.pinnedUserMessageID = nil
      scrollMode = .followBottom
      return [.scrollTo(target: .bottomSentinel, anchor: .bottom, animated: true)]
    }

    reservedTailSpace = remaining
    return []
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

    let desired = viewportHeight * 0.67
    let minTail: CGFloat = 320
    let maxTail: CGFloat = max(minTail, viewportHeight - 140)
    return min(max(desired, minTail), maxTail)
  }
}
