import SwiftUI
import AIKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public protocol PromptInputStyle: Sendable {
  associatedtype Body: View

  @MainActor
  @ViewBuilder
  func makeBody(configuration: PromptInputStyleConfiguration) -> Body
}

public struct PromptInputEditingContext {
  public var title: String
  public var onCancel: () -> Void
  public var onCommit: (_ text: String) -> Void

  public init(
    title: String = "Editing",
    onCancel: @escaping () -> Void,
    onCommit: @escaping (_ text: String) -> Void
  ) {
    self.title = title
    self.onCancel = onCancel
    self.onCommit = onCommit
  }
}

public struct PromptInputStyleConfiguration {
  public var text: Binding<String>
  public var status: ChatStatus
  public var placeholder: String
  public var attachments: [ChatFilePart]
  public var editing: PromptInputEditingContext?
  public var expandedBottomBar: AnyView?
  /// A monotonically increasing token; bump it to request focus on the prompt input.
  public var focusRequestID: Binding<Int>?
  public var onPasteImages: (([PlatformImage]) -> Void)?
  public var onSend: (String) -> Void
  public var onStop: () -> Void
  public var onAdd: (() -> Void)?

  public init(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String,
    attachments: [ChatFilePart] = [],
    editing: PromptInputEditingContext? = nil,
    expandedBottomBar: AnyView? = nil,
    focusRequestID: Binding<Int>? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)?
  ) {
    self.text = text
    self.status = status
    self.placeholder = placeholder
    self.attachments = attachments
    self.editing = editing
    self.expandedBottomBar = expandedBottomBar
    self.focusRequestID = focusRequestID
    self.onPasteImages = onPasteImages
    self.onSend = onSend
    self.onStop = onStop
    self.onAdd = onAdd
  }
}

public struct AnyPromptInputStyle {
  private let _makeBody: @MainActor (PromptInputStyleConfiguration) -> AnyView

  public init<S: PromptInputStyle>(_ style: S) {
    self._makeBody = { configuration in
      AnyView(style.makeBody(configuration: configuration))
    }
  }

  @MainActor
  func makeBody(configuration: PromptInputStyleConfiguration) -> AnyView {
    _makeBody(configuration)
  }
}

private struct PromptInputStyleStore: @unchecked Sendable {
  var value: AnyPromptInputStyle
}

private struct PromptInputStyleKey: EnvironmentKey {
  static let defaultValue = PromptInputStyleStore(value: AnyPromptInputStyle(StandardPromptInputStyle()))
}

extension EnvironmentValues {
  var promptInputStyle: AnyPromptInputStyle {
    get { self[PromptInputStyleKey.self].value }
    set { self[PromptInputStyleKey.self] = .init(value: newValue) }
  }
}

public extension View {
  func promptInputStyle<S: PromptInputStyle>(_ style: S) -> some View {
    environment(\.promptInputStyle, AnyPromptInputStyle(style))
  }
}
