import Foundation
import Observation

// Thin @Observable wrapper over ConversationScrollerCore. The core is the hot
// path and is @ObservationIgnored so mutating it at scroll rate never
// invalidates the view; the observable mirrors are written only when a value the
// view actually renders changes.
@MainActor
@Observable
final class ConversationScroller {
  @ObservationIgnored var core = ConversationScrollerCore()

  private(set) var spacerHeight: CGFloat = 0
  private(set) var isAtEnd: Bool = true
  private(set) var isFollowing: Bool = true
  private(set) var visibleCount: Int = ConversationScrollerConstants.messagePageSize
  private(set) var anchoredMessageID: String?

  func appear(rows: [ConversationScrollRow]) -> ConversationScrollCommand? {
    let command = core.handleAppear(rows: rows)
    syncMirrors()
    return command
  }

  func contentChange(
    rows: [ConversationScrollRow],
    rowGap: CGFloat,
    bottomContentPadding: CGFloat
  ) -> ConversationScrollCommand? {
    let command = core.handleContentChange(
      rows: rows,
      rowGap: rowGap,
      bottomContentPadding: bottomContentPadding
    )
    syncMirrors()
    return command
  }

  func geometryChange(_ geometry: ConversationScrollGeometry, totalDisplayCount: Int) -> ConversationScrollCommand? {
    let command = core.handleGeometryChange(geometry, totalDisplayCount: totalDisplayCount)
    syncMirrors()
    return command
  }

  func anchorRowFrame(viewportTop: CGFloat) -> ConversationScrollCommand? {
    let command = core.handleAnchorRowFrame(viewportTop: viewportTop)
    syncMirrors()
    return command
  }

  func endMarker(contentMaxY: CGFloat) -> ConversationScrollCommand? {
    let command = core.handleEndMarkerChange(contentMaxY: contentMaxY)
    syncMirrors()
    return command
  }

  func scrollToEndRequested() -> ConversationScrollCommand {
    let command = core.scrollToEndRequested()
    syncMirrors()
    return command
  }

  func scrollPhase(_ phase: ConversationScrollPhase) -> ConversationScrollCommand? {
    let command = core.handleScrollPhase(phase)
    syncMirrors()
    return command
  }

  private func syncMirrors() {
    if spacerHeight != core.spacerHeight { spacerHeight = core.spacerHeight }
    // The mirror feeds the jump-to-latest arrow. While following or jumping,
    // off-end frames are churn about to be re-pinned, not a reader position —
    // publishing them flickers the preference, and an edge emitted during a
    // sheet-presentation transaction is lost by onPreferenceChange, leaving
    // the arrow stuck. Only released modes report a real off-end position.
    let atEndForArrow = core.isAtEnd || core.mode == .followingBottom || core.mode == .settlingJump
    if isAtEnd != atEndForArrow { isAtEnd = atEndForArrow }
    if isFollowing != core.isFollowing { isFollowing = core.isFollowing }
    if visibleCount != core.visibleCount { visibleCount = core.visibleCount }
    if anchoredMessageID != core.anchoredRowID { anchoredMessageID = core.anchoredRowID }
  }
}
