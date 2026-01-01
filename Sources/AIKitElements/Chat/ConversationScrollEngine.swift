import CoreGraphics

/// A small, unit-testable "engine" for Conversation scrolling decisions.
///
/// The Conversation view remains responsible for executing scroll commands (via `ScrollViewProxy`),
/// but the logic that decides *what* should happen lives here.
enum ConversationScrollEngine {
  enum Mode: Equatable {
    case followBottom
    case pinUserMessageToTop(messageID: String)
  }

  enum ScrollTarget: Equatable {
    case bottomSentinel
    case reservedTailSentinel
    case message(String)
  }

  enum Anchor: Equatable {
    case top
    case bottom
  }

  enum Step: Equatable {
    case yield
    case setMode(Mode)
    case scrollTo(target: ScrollTarget, anchor: Anchor, animated: Bool)
    case reassertPinnedUserMessageIfNeeded(messageID: String)
  }

  struct Plan: Equatable {
    var steps: [Step]
  }

  struct LatestMetrics: Equatable {
    var viewportHeight: CGFloat
    var reservedTailSpace: CGFloat
    var bottomSentinelMaxY: CGFloat
    var tailSentinelMaxY: CGFloat

    public init(
      viewportHeight: CGFloat,
      reservedTailSpace: CGFloat,
      bottomSentinelMaxY: CGFloat,
      tailSentinelMaxY: CGFloat
    ) {
      self.viewportHeight = viewportHeight
      self.reservedTailSpace = reservedTailSpace
      self.bottomSentinelMaxY = bottomSentinelMaxY
      self.tailSentinelMaxY = tailSentinelMaxY
    }
  }

  static func computeIsAtLatest(metrics: LatestMetrics) -> Bool {
    if metrics.reservedTailSpace > 0 {
      return computeIsAtLatest(maxY: metrics.tailSentinelMaxY, viewportHeight: metrics.viewportHeight)
    }
    return computeIsAtLatest(maxY: metrics.bottomSentinelMaxY, viewportHeight: metrics.viewportHeight)
  }

  static func computeIsAtLatest(maxY: CGFloat, viewportHeight: CGFloat) -> Bool {
    guard viewportHeight.isFinite, viewportHeight > 0 else { return false }
    guard maxY.isFinite, maxY >= 0 else { return false }

    // Consider "at latest" when the sentinel is at (or above) the viewport bottom.
    //
    // During rubber-banding at the bottom, the sentinel can be *above* the viewport bottom (maxY < viewportHeight),
    // which still means we're already as far down as the content can go — the extra scroll is just overscroll.
    let threshold: CGFloat = 2.5
    return maxY <= (viewportHeight + threshold)
  }

  /// Produces the programmatic scrolling sequence for "anchor new user message to top".
  ///
  /// The intent is to end at the latest scroll position while in "pinned" mode, so the newly sent user message
  /// is positioned near the top with reserved tail space below it.
  static func planForSendAnchoring(userMessageID: String, hasReservedTailSpace: Bool) -> Plan {
    let latestTarget: ScrollTarget = hasReservedTailSpace ? .reservedTailSentinel : .bottomSentinel
    return Plan(steps: [
      .yield,
      .setMode(.pinUserMessageToTop(messageID: userMessageID)),
      .yield,
      .scrollTo(target: latestTarget, anchor: .bottom, animated: true),
      .yield,
      .yield,
      .reassertPinnedUserMessageIfNeeded(messageID: userMessageID),
    ])
  }
}
