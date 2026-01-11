import Foundation
import SwiftUI

private struct ChatSheetDetentSelectionKey: EnvironmentKey {
  static let defaultValue: Binding<PresentationDetent>? = nil
}

private struct ChatSheetSupportedDetentsKey: EnvironmentKey {
  static let defaultValue: Set<PresentationDetent> = []
}

private struct ChatSheetKeepsExpandedOnSendKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension EnvironmentValues {
  var chatSheetDetentSelection: Binding<PresentationDetent>? {
    get { self[ChatSheetDetentSelectionKey.self] }
    set { self[ChatSheetDetentSelectionKey.self] = newValue }
  }

  var chatSheetSupportedDetents: Set<PresentationDetent> {
    get { self[ChatSheetSupportedDetentsKey.self] }
    set { self[ChatSheetSupportedDetentsKey.self] = newValue }
  }

  var chatSheetKeepsExpandedOnSend: Bool {
    get { self[ChatSheetKeepsExpandedOnSendKey.self] }
    set { self[ChatSheetKeepsExpandedOnSendKey.self] = newValue }
  }
}

private struct ChatSheetDefaultsModifier: ViewModifier {
  let detents: Set<PresentationDetent>
  let initialDetent: PresentationDetent
  let dragIndicator: Visibility
  let contentInteraction: PresentationContentInteraction
  let keepsExpandedOnSend: Bool

  @State private var selectedDetent: PresentationDetent

  init(
    detents: Set<PresentationDetent>,
    initialDetent: PresentationDetent,
    dragIndicator: Visibility,
    contentInteraction: PresentationContentInteraction,
    keepsExpandedOnSend: Bool
  ) {
    self.detents = detents
    self.initialDetent = initialDetent
    self.dragIndicator = dragIndicator
    self.contentInteraction = contentInteraction
    self.keepsExpandedOnSend = keepsExpandedOnSend

    let resolvedInitialDetent: PresentationDetent = if detents.contains(initialDetent) {
      initialDetent
    } else if detents.contains(.medium) {
      .medium
    } else if detents.contains(.large) {
      .large
    } else {
      detents.first ?? .large
    }

    _selectedDetent = State(initialValue: resolvedInitialDetent)
  }

  func body(content: Content) -> some View {
    content
      .presentationDetents(detents, selection: $selectedDetent)
      .presentationContentInteraction(contentInteraction)
      .presentationDragIndicator(dragIndicator)
      .environment(\.chatSheetDetentSelection, $selectedDetent)
      .environment(\.chatSheetSupportedDetents, detents)
      .environment(\.chatSheetKeepsExpandedOnSend, keepsExpandedOnSend)
  }
}

public extension View {
  /// Applies default SwiftUI sheet configuration for embedding a chat conversation in a resizable sheet.
  ///
  /// In a resizable sheet, SwiftUI defaults to resizing the sheet before letting an embedded `ScrollView`
  /// scroll. Chat UIs typically want the opposite: scroll the conversation first, and let the user resize
  /// using the drag indicator.
  public func chatSheetDefaults(
    detents: Set<PresentationDetent> = [.medium, .large],
    initialDetent: PresentationDetent = .medium,
    dragIndicator: Visibility = .visible,
    contentInteraction: PresentationContentInteraction = .scrolls,
    keepsExpandedOnSend: Bool = true
  ) -> some View {
    modifier(ChatSheetDefaultsModifier(
      detents: detents,
      initialDetent: initialDetent,
      dragIndicator: dragIndicator,
      contentInteraction: contentInteraction,
      keepsExpandedOnSend: keepsExpandedOnSend
    ))
  }
}
