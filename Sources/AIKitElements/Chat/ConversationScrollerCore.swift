import CoreGraphics
import Foundation

// Pure, SwiftUI-free port of shadcn's MessageScroller behavior model
// (packages/react/src/message-scroller): a four-state mode machine plus pure
// geometry. The view layer (`ConversationScroller` / `Conversation`) feeds it
// geometry/content/phase events and executes the `ConversationScrollCommand`s
// it returns. All decisions live here so they can be unit-tested without a
// viewport.
//
// Commands are layout-resolved wherever possible (`toEnd`, `toRowTop` run
// through a ScrollViewProxy): during bar/keyboard transitions the system walks
// the offset to preserve the visual top, and lazy row estimates shift the
// content height, so absolute-offset math is only trustworthy for anchor
// placement on a settled viewport (`toOffset`).

enum ConversationScrollerConstants {
  // Sub-pixel tolerance so edge detection does not flicker across rounding drift.
  static let scrollEdgeThreshold: CGFloat = 8
  // Pixels of the previous turn kept visible above a newly anchored row.
  static let previousItemPeek: CGFloat = 64
  // Two offsets within this range are treated as equal.
  static let positionEpsilon: CGFloat = 0.5
  // Breathing room between the last message and the bottom overlay.
  static let extraBottomPadding: CGFloat = 24
  static let messagePageSize: Int = 60
  // Distance from the top edge that triggers loading older messages.
  static let loadOlderTopThreshold: CGFloat = 300
}

// Equatable snapshot of the scroll viewport. `contentHeight` is the scroll
// view's own contentSize — a lazy-layout ESTIMATE, only good for classifying
// frames as layout churn. Positions are measured against the end marker, which
// is layout truth.
struct ConversationScrollGeometry: Equatable {
  var offsetY: CGFloat = 0
  var contentHeight: CGFloat = 0
  var containerHeight: CGFloat = 0
  var topInset: CGFloat = 0
  var bottomInset: CGFloat = 0
}

// Internal scroll mode. Decides how the viewport reacts to content and resize.
enum ConversationScrollMode: Equatable {
  case followingBottom   // pinned to the latest message.
  case freeScrolling     // reader scrolled away; position left alone.
  case anchoredToMessage // holding a turn at the reading line while it streams.
  case settlingJump      // a programmatic jump is animating; intent suppressed until it settles.
}

// A move the view should perform. `toEnd` and `toRowTop` are executed
// layout-resolved via ScrollViewProxy; `toOffset` via ScrollPosition.
enum ConversationScrollCommand: Equatable {
  case toEnd(animated: Bool)
  case toOffset(y: CGFloat)
  case toRowTop(id: String)
}

// One transcript row as the core sees it: a stable id and whether it anchors
// (a user turn, when anchoring is enabled).
struct ConversationScrollRow: Equatable {
  var id: String
  var isAnchor: Bool
}

struct ConversationScrollerCore {
  private typealias K = ConversationScrollerConstants

  var mode: ConversationScrollMode = .followingBottom
  var spacerHeight: CGFloat = 0
  var geometry = ConversationScrollGeometry()
  var visibleCount: Int = ConversationScrollerConstants.messagePageSize

  private(set) var knownRowIDs: [String] = []
  private(set) var handledAnchorIDs: Set<String> = []
  var anchoredRowID: String?

  // Content-space bottom of the end marker — the layout-true content bottom
  // (the marker sits after the rows and before the tail spacer, in the
  // non-lazy outer stack, measured in a content-fixed coordinate space). The
  // scroll view's contentSize is a lazy estimate and can be ~100pt off at
  // rest, so at-end detection, anchor placement, and spacer math all measure
  // against the marker instead. Content coordinates are scroll-invariant:
  // this value changes only on real layout changes, so pairing it with any
  // frame's offset always yields a coherent distance — the two measurement
  // streams can never race each other. Crucially, `toEnd` scrolls to the same
  // marker, so estimate error cancels out of "am I at the thing I scroll to".
  var endMarkerContentMaxY: CGFloat = .greatestFiniteMagnitude

  // The offset the anchored turn is held at; the spacer is recomputed against it
  // as the reply streams so the turn holds still and the spacer shrinks 1:1.
  private var anchoredTargetOffset: CGFloat?

  // MARK: - Derived

  // The marker sits before the tail spacer, so the distance excludes the
  // spacer and a freshly anchored short turn still counts as at-end. Zero is
  // calibrated to the rest position of the toEnd pin itself: contentY maps to
  // viewport coordinates as contentY − offset − topInset, and the pin rests
  // with the marker at the viewport's containerHeight.
  var distanceFromEnd: CGFloat {
    endMarkerContentMaxY - geometry.offsetY - geometry.topInset - geometry.containerHeight
  }

  var isAtEnd: Bool {
    distanceFromEnd <= K.scrollEdgeThreshold
  }

  // Streaming growth is followed natively: the view sets
  // `defaultScrollAnchor(.bottom, for: .sizeChanges)` while this is true.
  // (ScrollPosition.scrollTo(edge:) is state-diffed and drops repeated pins,
  // so per-tick pin commands cannot implement follow.)
  var isFollowing: Bool {
    mode == .followingBottom
  }

  // MARK: - Events

  mutating func handleAppear(rows: [ConversationScrollRow]) -> ConversationScrollCommand? {
    knownRowIDs = rows.map(\.id)
    // A saved transcript opens at the end with every anchor already handled, so
    // history never yanks the reader to an old turn.
    handledAnchorIDs = Set(rows.filter(\.isAnchor).map(\.id))
    anchoredRowID = nil
    anchoredTargetOffset = nil
    spacerHeight = 0
    mode = .followingBottom
    guard rows.isEmpty == false else { return nil }
    return .toEnd(animated: false)
  }

  // Branch order is load-bearing (mirrors use-message-scroller-controller.ts):
  // first-content, prepended, appended, updated, then follow-or-idle.
  mutating func handleContentChange(
    rows: [ConversationScrollRow],
    rowGap: CGFloat,
    bottomContentPadding: CGFloat
  ) -> ConversationScrollCommand? {
    let previousIDs = knownRowIDs
    let previousCount = previousIDs.count
    let previousFirst = previousIDs.first
    let newIDs = rows.map(\.id)
    defer { knownRowIDs = newIDs }

    // First content: the size-change anchor pins the bottom natively.
    if previousCount == 0 {
      handledAnchorIDs = Set(rows.filter(\.isAnchor).map(\.id))
      mode = .followingBottom
      return nil
    }

    // Prepended (older messages paged in): the prior first row is now deeper in
    // the list. Keep it visually stable by re-pinning it to the top, and mark
    // the newly shown history handled so it never anchors.
    if let previousFirst, let index = newIDs.firstIndex(of: previousFirst), index > 0 {
      handledAnchorIDs.formUnion(rows.filter(\.isAnchor).map(\.id))
      return .toRowTop(id: previousFirst)
    }

    // Appended.
    if rows.count > previousCount {
      let appended = rows.suffix(rows.count - previousCount)
      let newAnchors = appended.filter(\.isAnchor)
      if let anchor = newAnchors.first {
        // Every appended anchor counts as seen, so a later same-count update
        // can only anchor to a genuinely new (edited/replaced) row.
        handledAnchorIDs.formUnion(newAnchors.map(\.id))
        // A batch of several anchored turns arriving while following keeps
        // following the end (natively) rather than yanking back to the first
        // of the batch.
        if mode == .followingBottom, newAnchors.count > 1 {
          return nil
        }
        return beginAnchor(to: anchor.id, rowGap: rowGap, bottomContentPadding: bottomContentPadding)
      }
    }

    // Updated (same count, e.g. an edited/replaced user message with a new id).
    if rows.count == previousCount {
      if let anchor = rows.first(where: { $0.isAnchor && handledAnchorIDs.contains($0.id) == false }) {
        handledAnchorIDs.insert(anchor.id)
        return beginAnchor(to: anchor.id, rowGap: rowGap, bottomContentPadding: bottomContentPadding)
      }
    }

    // Appends with no new anchor and content-only updates: the size-change
    // anchor keeps following natively.
    return nil
  }

  mutating func handleGeometryChange(_ next: ConversationScrollGeometry, totalDisplayCount: Int) -> ConversationScrollCommand? {
    let previous = geometry
    geometry = next

    // Anchored: hold the turn and shrink the spacer as the reply grows below it.
    if mode == .anchoredToMessage, let target = anchoredTargetOffset {
      updateSpacer(forTargetOffset: target)
      return nil
    }

    // Arrival at the end settles a jump into following even when no .idle
    // phase fires (e.g. macOS scrollbar drags emit no phase events).
    if mode == .settlingJump {
      if isAtEnd { mode = .followingBottom }
      return nil
    }

    // A pure-offset frame is a real scroll (or the landing of a command, which
    // is safe: an end pin lands at the end and never matches the release
    // condition). Anything else is layout churn — content growth, lazy row
    // estimates settling, insets or the container changing. Only a real scroll
    // releases follow; churn off the end re-pins. The pin is layout-resolved
    // (toEnd), so it lands at the true end no matter how the estimates or
    // insets are moving.
    let layoutChanged = abs(next.contentHeight - previous.contentHeight) > K.positionEpsilon
      || abs(next.containerHeight - previous.containerHeight) > K.positionEpsilon
      || abs(next.topInset - previous.topInset) > K.positionEpsilon
      || abs(next.bottomInset - previous.bottomInset) > K.positionEpsilon
    let offsetChanged = abs(next.offsetY - previous.offsetY) > K.positionEpsilon

    if mode == .followingBottom {
      if layoutChanged {
        if isAtEnd == false {
          return .toEnd(animated: false)
        }
      } else if offsetChanged, isAtEnd == false {
        mode = .freeScrolling
      }
      return nil
    }

    // Free-scrolling: being back at the end re-arms follow; nearing the top
    // loads an older page (once the previous page has landed in the rows).
    if mode == .freeScrolling {
      if canRearmFollow {
        rearmFollow()
      } else if isAtEnd == false, visibleCount <= knownRowIDs.count,
                visibleCount < totalDisplayCount,
                next.offsetY + next.topInset < K.loadOlderTopThreshold {
        visibleCount += K.messagePageSize
      }
    }
    return nil
  }

  // The end marker's content position changes only on real layout changes
  // (never on scrolling), so a pin issued here is always a genuine content
  // drift correction — the streaming-growth backstop when the native anchor
  // misses, and the final correction after a layout storm.
  mutating func handleEndMarkerChange(contentMaxY: CGFloat) -> ConversationScrollCommand? {
    endMarkerContentMaxY = contentMaxY
    if mode == .anchoredToMessage, let target = anchoredTargetOffset {
      updateSpacer(forTargetOffset: target)
      return nil
    }
    if mode == .followingBottom, isAtEnd == false {
      return .toEnd(animated: false)
    }
    return nil
  }

  // Called with the anchored row's viewport-relative top; corrects the estimated
  // placement once the row has really laid out. Row frames arrive in
  // frame(in: .scrollView) coordinates, whose origin is the inset-adjusted
  // content edge (just below the top overlay/bar), so the reading line is the
  // peek alone — adding topInset here would double-count it (verified in the
  // sheet demo: the anchored row converged exactly topInset below the line).
  mutating func handleAnchorRowFrame(viewportTop: CGFloat) -> ConversationScrollCommand? {
    guard mode == .anchoredToMessage, anchoredRowID != nil else { return nil }
    let readingLine = K.previousItemPeek
    let delta = viewportTop - readingLine
    guard abs(delta) > K.positionEpsilon else {
      if let target = anchoredTargetOffset { updateSpacer(forTargetOffset: target) }
      return nil
    }
    let target = max(0, geometry.offsetY + delta)
    anchoredTargetOffset = target
    updateSpacer(forTargetOffset: target)
    return .toOffset(y: target)
  }

  mutating func userScrollIntent() {
    switch mode {
    case .followingBottom, .anchoredToMessage, .settlingJump:
      // A deliberate gesture releases follow, anchoring, and an in-flight jump so
      // re-pinning never fights the reader. The spacer is left untouched.
      anchoredRowID = nil
      anchoredTargetOffset = nil
      mode = .freeScrolling
    case .freeScrolling:
      break
    }
  }

  mutating func scrollToEndRequested() -> ConversationScrollCommand {
    spacerHeight = 0
    anchoredRowID = nil
    anchoredTargetOffset = nil
    mode = .settlingJump
    return .toEnd(animated: true)
  }

  mutating func handleScrollPhase(_ phase: ConversationScrollPhase) -> ConversationScrollCommand? {
    switch phase {
    case .interacting:
      userScrollIntent()
      return nil
    case .idle:
      // A jump that settled short of the end (lazy row estimates shifted the
      // content mid-flight) is reasserted; toEnd is layout-resolved, so the
      // retry converges.
      if mode == .settlingJump {
        if isAtEnd {
          mode = .followingBottom
          return nil
        }
        return .toEnd(animated: true)
      }
      if mode == .freeScrolling, canRearmFollow {
        rearmFollow()
      }
      return nil
    case .tracking, .animating, .decelerating:
      // A resting finger, a programmatic animation, and post-flick settling
      // must not release modes; .interacting is the deliberate gesture.
      return nil
    }
  }

  // MARK: - Mode transitions

  // Re-arm only within the edge threshold of the REAL end, where any leftover
  // tail spacer extends below the fold and dropping it removes invisible
  // scroll range with no visual change. Deeper in the spacer (a freshly
  // anchored turn the reader just grabbed) isAtEnd is also true, but dropping
  // the spacer there would clamp the offset and snap the view against the
  // reader's finger — stay released until the reader returns to the real end.
  private var canRearmFollow: Bool {
    abs(distanceFromEnd) <= K.scrollEdgeThreshold
  }

  private mutating func rearmFollow() {
    spacerHeight = 0
    mode = .followingBottom
  }

  // MARK: - Anchoring

  private mutating func beginAnchor(
    to id: String,
    rowGap: CGFloat,
    bottomContentPadding: CGFloat
  ) -> ConversationScrollCommand {
    // First placement is an estimate: the new anchor lands one row gap below
    // the last row, which sits bottomContentPadding above the real content
    // bottom. The offset that puts content position C at the reading line is
    // C − topInset − readingLine (readingLine is the peek, measured from the
    // inset-adjusted content edge — same space as handleAnchorRowFrame).
    // handleAnchorRowFrame corrects the residual once the row lays out.
    let estimatedRowTop = endMarkerContentMaxY - bottomContentPadding + rowGap
    let readingLine = K.previousItemPeek
    let estimatedTarget = max(0, estimatedRowTop - geometry.topInset - readingLine)
    anchoredRowID = id
    anchoredTargetOffset = estimatedTarget
    mode = .anchoredToMessage
    updateSpacer(forTargetOffset: estimatedTarget)
    return .toOffset(y: estimatedTarget)
  }

  // Grows the tail spacer so the target offset is reachable and the real content
  // fills to the viewport bottom; shrinks it 1:1 as content grows. Reachability
  // uses the same pin-calibrated ruler as distanceFromEnd: the maximum offset
  // is (content bottom incl. spacer) − topInset − containerHeight.
  private mutating func updateSpacer(forTargetOffset target: CGFloat) {
    spacerHeight = max(0, target + geometry.topInset + geometry.containerHeight - endMarkerContentMaxY)
  }
}

// SwiftUI-free mirror of the scroll phases the core reacts to.
enum ConversationScrollPhase {
  case idle
  case tracking
  case interacting
  case animating
  case decelerating
}
