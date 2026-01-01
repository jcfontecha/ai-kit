import SwiftUI

public extension View {
  /// Applies default SwiftUI sheet configuration for embedding a chat conversation in a resizable sheet.
  ///
  /// In a resizable sheet, SwiftUI defaults to resizing the sheet before letting an embedded `ScrollView`
  /// scroll. Chat UIs typically want the opposite: scroll the conversation first, and let the user resize
  /// using the drag indicator.
  func chatSheetDefaults(
    detents: Set<PresentationDetent> = [.medium, .large],
    dragIndicator: Visibility = .visible,
    contentInteraction: PresentationContentInteraction = .scrolls
  ) -> some View {
    presentationDetents(detents)
      .presentationContentInteraction(contentInteraction)
      .presentationDragIndicator(dragIndicator)
  }
}

