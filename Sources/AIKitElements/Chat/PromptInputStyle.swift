import SwiftUI
import AIKit

public protocol PromptInputStyle: Sendable {
  associatedtype Body: View

  @MainActor
  @ViewBuilder
  func makeBody(configuration: PromptInputStyleConfiguration) -> Body
}

public struct PromptInputStyleConfiguration {
  public var text: Binding<String>
  public var status: ChatStatus
  public var placeholder: String
  public var onSend: (String) -> Void
  public var onStop: () -> Void
  public var onAdd: (() -> Void)?

  public init(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)?
  ) {
    self.text = text
    self.status = status
    self.placeholder = placeholder
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
