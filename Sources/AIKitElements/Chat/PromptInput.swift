import SwiftUI
import AIKit

#if os(macOS)
import AppKit
#endif

#if os(macOS)
private struct PromptInputMacTextField: NSViewRepresentable {
  @Binding var text: String
  let placeholder: String

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(string: text)
    field.placeholderString = placeholder
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = NSFont.preferredFont(forTextStyle: .body)
    field.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [.foregroundColor: NSColor.labelColor.withAlphaComponent(0.6)]
    )
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ nsView: NSTextField, context: Context) {
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    @Binding private var text: String

    init(text: Binding<String>) {
      self._text = text
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      text = field.stringValue
    }
  }
}
#endif

public struct PromptInputField: View {
  @Binding public var text: String
  public var status: ChatStatus
  public var placeholder: String
  public var onSend: (String) -> Void
  public var onStop: () -> Void

  // Tuning knobs
  private let pillContentLeadingPadding: CGFloat = 10
  private let pillContentVerticalPadding: CGFloat = 12
  private let pillToControlPadding: CGFloat = 8
  private let trailingControlInset: CGFloat = 6
  private let controlSize: CGFloat = 30
  private let controlIconSize: CGFloat = 16
  private var controlIconPadding: CGFloat { (controlSize - controlIconSize) / 2 }

  public init(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void
  ) {
    self._text = text
    self.status = status
    self.placeholder = placeholder
    self.onSend = onSend
    self.onStop = onStop
  }

  public var body: some View {
    composerField
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .disabled(status == .streaming || status == .submitted)
      // Reserve space so multi-line text doesn't flow under the trailing control.
      .padding(.trailing, trailingControlWidth + trailingControlInset)
      .padding(.leading, pillContentLeadingPadding)
      .padding(.vertical, pillContentVerticalPadding)
      .overlay(alignment: .bottomTrailing) {
        trailingControl
          .padding([.trailing, .top, .bottom], pillToControlPadding)
      }
  }

  private var sendEnabled: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }

  private var enabledControlForeground: Color {
    #if os(iOS) || os(tvOS) || os(watchOS)
    Color(uiColor: .systemBackground)
    #elseif os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color.white
    #endif
  }

  private var enabledControlBackground: Color {
    #if os(iOS) || os(tvOS) || os(watchOS)
    Color(uiColor: .label)
    #elseif os(macOS)
    Color(nsColor: .labelColor)
    #else
    Color.black
    #endif
  }

  private var trailingControlWidth: CGFloat { controlSize }

  @ViewBuilder
  private var trailingControl: some View {
    if status == .streaming || status == .submitted {
      Button(action: onStop) {
        Image(systemName: "stop.fill")
          .frame(width: controlIconSize, height: controlIconSize)
          .padding(controlIconPadding)
          .foregroundStyle(Color.platformBackground)
          .background { Circle().fill(enabledControlBackground) }
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
          .foregroundStyle(enabledControlForeground)
          .background { Circle().fill(enabledControlBackground) }
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
      TextField(
        placeholder,
        text: $text,
        prompt: Text(placeholder).foregroundStyle(Color.primary.opacity(0.6)),
        axis: .vertical
      )
        .textFieldStyle(.plain)
        .font(.body)
        .lineLimit(1...6)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 6)
    #else
    PromptInputMacTextField(text: $text, placeholder: placeholder)
    #endif
  }
}

public struct StandardPromptInputStyle: PromptInputStyle {
  public init() {}

  public func makeBody(configuration: PromptInputStyleConfiguration) -> some View {
    StandardPromptInput(configuration: configuration)
  }
}

private struct StandardPromptInput: View {
  let configuration: PromptInputStyleConfiguration

  private let cornerRadius: CGFloat = 24
  private let plusButtonIconSize: CGFloat = 18
  private let plusButtonPadding: CGFloat = 14
  private let plusButtonSpacing: CGFloat = 8
  private var plusButtonSize: CGFloat { plusButtonIconSize + (plusButtonPadding * 2) }
  private let bottomInset: CGFloat = 4

  var body: some View {
    GlassEffectContainer(spacing: plusButtonSpacing) {
      HStack(alignment: .bottom, spacing: plusButtonSpacing) {
        if configuration.onAdd != nil {
          plusButton
        }
        PromptInputField(
          text: configuration.text,
          status: configuration.status,
          placeholder: configuration.placeholder,
          onSend: configuration.onSend,
          onStop: configuration.onStop
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: plusButtonSize, alignment: .center)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: cornerRadius))
      }
    }
    .padding(.bottom, bottomInset)
    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 0)
  }

  private var plusButton: some View {
    let action = configuration.onAdd ?? {}
    return Button(action: action) {
      Image(systemName: "plus")
        .frame(width: plusButtonSize, height: plusButtonSize)
        .font(.system(size: plusButtonIconSize, weight: .medium))
        .foregroundStyle(plusIconColor)
        .glassEffect(.clear.interactive(), in: .circle)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
  }

  private var plusIconColor: Color {
    #if os(iOS) || os(tvOS) || os(watchOS)
    Color(uiColor: .label)
    #elseif os(macOS)
    Color(nsColor: .labelColor)
    #else
    Color.primary
    #endif
  }
}

public struct PromptInput: View {
  @Binding public var text: String
  public var status: ChatStatus
  public var placeholder: String
  public var onSend: (String) -> Void
  public var onStop: () -> Void
  public var onAdd: (() -> Void)?

  @Environment(\.promptInputStyle) private var style

  public init(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil
  ) {
    self._text = text
    self.status = status
    self.placeholder = placeholder
    self.onSend = onSend
    self.onStop = onStop
    self.onAdd = onAdd
  }

  public var body: some View {
    style.makeBody(configuration: .init(
      text: $text,
      status: status,
      placeholder: placeholder,
      onSend: onSend,
      onStop: onStop,
      onAdd: onAdd
    ))
  }
}

public extension View {
  func chatComposer(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    showsScrollToLatestButton: Bool = true,
    overlayPadding: CGFloat = 8,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil
  ) -> some View {
    modifier(ChatComposerModifier(
      text: text,
      status: status,
      placeholder: placeholder,
      height: nil,
      showsScrollToLatestButton: showsScrollToLatestButton,
      overlayPadding: overlayPadding,
      onSend: onSend,
      onStop: onStop,
      onAdd: onAdd
    ))
  }

  func promptInputBottomBar(
    text: Binding<String>,
    status: ChatStatus,
    height: Binding<CGFloat>,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil
  ) -> some View {
    modifier(
      ChatComposerModifier(
        text: text,
        status: status,
        placeholder: "Message",
        height: height,
        showsScrollToLatestButton: false,
        overlayPadding: 0,
        onSend: onSend,
        onStop: onStop,
        onAdd: onAdd
      )
    )
  }
}

private struct ChatComposerModifier: ViewModifier {
  @Binding var text: String
  let status: ChatStatus
  let placeholder: String
  var height: Binding<CGFloat>?
  let showsScrollToLatestButton: Bool
  let overlayPadding: CGFloat
  let onSend: (String) -> Void
  let onStop: () -> Void
  let onAdd: (() -> Void)?

  @State private var measuredHeight: CGFloat = 0

  func body(content: Content) -> some View {
    let resolvedHeight = height?.wrappedValue ?? measuredHeight

    #if os(iOS)
    content
      // Keep the main content (e.g. `Conversation`) extending behind the composer for depth.
      .ignoresSafeArea(.container, edges: .bottom)
      .conversationBottomOverlayHeight(resolvedHeight + overlayPadding)
      .conversationShowsScrollToLatestButton(showsScrollToLatestButton)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        PromptInput(
          text: $text,
          status: status,
          placeholder: placeholder,
          onSend: onSend,
          onStop: onStop,
          onAdd: onAdd
        )
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 26)
          .background {
            GeometryReader { proxy in
              Color.clear
                .onAppear { updateMeasuredHeight(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, newHeight in
                  updateMeasuredHeight(newHeight)
                }
            }
          }
      }
    #else
    content
      .conversationBottomOverlayHeight(resolvedHeight + overlayPadding)
      .conversationShowsScrollToLatestButton(showsScrollToLatestButton)
      .safeAreaInset(edge: .bottom) {
        PromptInput(
          text: $text,
          status: status,
          placeholder: placeholder,
          onSend: onSend,
          onStop: onStop,
          onAdd: onAdd
        )
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 8)
          .background {
            GeometryReader { proxy in
              Color.clear
                .onAppear { updateMeasuredHeight(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, newHeight in
                  updateMeasuredHeight(newHeight)
                }
            }
          }
      }
    #endif
  }

  private func updateMeasuredHeight(_ newHeight: CGFloat) {
    measuredHeight = newHeight
    height?.wrappedValue = newHeight
  }
}

// Height measurement is handled in-place (GeometryReader) to avoid preference propagation issues across `safeAreaInset`.
