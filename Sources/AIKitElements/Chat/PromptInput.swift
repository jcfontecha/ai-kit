import SwiftUI
import AIKit

public struct PromptInputElements: View {
  @Binding public var text: String
  public var status: ChatSessionStatus
  public var onSend: (String) -> Void
  public var onStop: () -> Void

  // Tuning knobs
  private let pillContentLeadingPadding: CGFloat = 10
  private let pillContentVerticalPadding: CGFloat = 5
  private let pillToControlPadding: CGFloat = 7
  private let trailingControlInset: CGFloat = 6
  private let controlIconSize: CGFloat = 16
  private let controlIconPadding: CGFloat = 10

  public init(
    text: Binding<String>,
    status: ChatSessionStatus,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void
  ) {
    self._text = text
    self.status = status
    self.onSend = onSend
    self.onStop = onStop
  }

  public var body: some View {
    ZStack(alignment: .bottomTrailing) {
      composerField
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(status == .streaming || status == .submitted)
        // Reserve space so multi-line text doesn't flow under the trailing control.
        .padding(.trailing, trailingControlWidth + trailingControlInset)
        .padding(.leading, pillContentLeadingPadding)
        .padding(.vertical, pillContentVerticalPadding)
        .padding(.bottom, pillContentVerticalPadding + 3)

      trailingControl
            .padding([.trailing, .top, .bottom], pillToControlPadding)
    }
  }

  private var sendEnabled: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }

  private var trailingControlWidth: CGFloat {
    controlIconSize + (controlIconPadding * 2)
  }

  @ViewBuilder
  private var trailingControl: some View {
    if status == .streaming || status == .submitted {
      Button(action: onStop) {
        Image(systemName: "stop.fill")
          .frame(width: controlIconSize, height: controlIconSize)
          .padding(controlIconPadding)
          .foregroundStyle(Color.platformBackground)
          .background {
            Circle().fill(Color.primary)
          }
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Stop")
    } else {
      Button {
        let msg = text
        text = ""
        onSend(msg)
      } label: {
        Image(systemName: "arrow.up")
          .frame(width: controlIconSize, height: controlIconSize)
          .padding(controlIconPadding)
          .foregroundStyle(sendEnabled ? Color.platformBackground : Color.platformBackground.opacity(0.55))
          .background {
            Circle()
              .fill(sendEnabled ? Color.primary : Color.primary.opacity(0.30))
          }
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(sendEnabled == false)
      .accessibilityLabel("Send")
    }
  }

  @ViewBuilder
  private var composerField: some View {
    #if os(iOS)
    if #available(iOS 16.0, *) {
      TextField("Message", text: $text, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...6)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 6)
    } else {
      TextField("Message", text: $text)
        .textFieldStyle(.plain)
    }
    #else
    TextField("Message", text: $text)
      .textFieldStyle(.plain)
    #endif
  }
}

public struct PromptInput: View {
  @Binding public var text: String
  public var status: ChatSessionStatus
  public var onSend: (String) -> Void
  public var onStop: () -> Void

  private let cornerRadius: CGFloat = 24

  public init(
    text: Binding<String>,
    status: ChatSessionStatus,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void
  ) {
    self._text = text
    self.status = status
    self.onSend = onSend
    self.onStop = onStop
  }

  public var body: some View {
    PromptInputElements(text: $text, status: status, onSend: onSend, onStop: onStop)
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(Color.clear)
          .glassSurface(cornerRadius: cornerRadius)
      }
  }
}

public extension View {
  func promptInputBottomBar(
    text: Binding<String>,
    status: ChatSessionStatus,
    height: Binding<CGFloat>,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void
  ) -> some View {
    modifier(
      PromptInputBottomBarModifier(
        text: text,
        status: status,
        height: height,
        onSend: onSend,
        onStop: onStop
      )
    )
  }
}

private struct PromptInputBottomBarModifier: ViewModifier {
  @Binding var text: String
  let status: ChatSessionStatus
  @Binding var height: CGFloat
  let onSend: (String) -> Void
  let onStop: () -> Void

  func body(content: Content) -> some View {
    #if os(iOS)
    content
      // Keep the main content (e.g. `Conversation`) extending behind the composer for depth.
      .ignoresSafeArea(.container, edges: .bottom)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        PromptInput(text: $text, status: status, onSend: onSend, onStop: onStop)
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 8)
          .background {
            GeometryReader { proxy in
              Color.clear
                .onAppear { height = proxy.size.height }
                .onChange(of: proxy.size.height) { newHeight in
                  height = newHeight
                }
            }
          }
      }
    #else
    content
      .safeAreaInset(edge: .bottom) {
        PromptInput(text: $text, status: status, onSend: onSend, onStop: onStop)
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 12)
          .background {
            GeometryReader { proxy in
              Color.clear
                .onAppear { height = proxy.size.height }
                .onChange(of: proxy.size.height) { newHeight in
                  height = newHeight
                }
            }
          }
      }
    #endif
  }
}

// Height measurement is handled in-place (GeometryReader) to avoid preference propagation issues across `safeAreaInset`.
