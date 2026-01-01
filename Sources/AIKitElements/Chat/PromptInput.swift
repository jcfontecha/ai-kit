import SwiftUI
import AIKit

#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#endif

#if os(iOS)
private struct PromptInputiOSTextField: UIViewRepresentable {
  @Binding var text: String
  @Binding var measuredHeight: CGFloat
  let placeholder: String
  let onPasteImages: (([UIImage]) -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, measuredHeight: $measuredHeight, onPasteImages: onPasteImages)
  }

  func makeUIView(context: Context) -> UITextView {
    let view = PasteAwareTextView()
    view.text = text
    view.backgroundColor = .clear
    view.font = UIFont.preferredFont(forTextStyle: .body)
    view.delegate = context.coordinator
    view.isScrollEnabled = false
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.textContainer.lineBreakMode = .byWordWrapping
    view.textContainer.widthTracksTextView = true
    view.onPasteImages = context.coordinator.onPasteImages
    view.placeholderLabel.text = placeholder
    view.placeholderLabel.isHidden = text.isEmpty == false
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)

    context.coordinator.updateHeight(for: view)
    return view
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    if uiView.text != text {
      uiView.text = text
    }
    if let pasteView = uiView as? PasteAwareTextView {
      pasteView.onPasteImages = context.coordinator.onPasteImages
    }
    if let pasteView = uiView as? PasteAwareTextView {
      pasteView.placeholderLabel.text = placeholder
      pasteView.placeholderLabel.isHidden = uiView.text.isEmpty == false
    }

    context.coordinator.updateHeight(for: uiView)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize {
    let targetWidth = proposal.width ?? uiView.bounds.width
    let resolvedWidth = max(0, targetWidth)

    uiView.layoutIfNeeded()
    let size = uiView.sizeThatFits(CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude))
    return CGSize(width: resolvedWidth, height: size.height)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    @Binding private var text: String
    @Binding private var measuredHeight: CGFloat
    let onPasteImages: (([UIImage]) -> Void)?

    init(
      text: Binding<String>,
      measuredHeight: Binding<CGFloat>,
      onPasteImages: (([UIImage]) -> Void)?
    ) {
      self._text = text
      self._measuredHeight = measuredHeight
      self.onPasteImages = onPasteImages
    }

    func textViewDidChange(_ textView: UITextView) {
      text = textView.text
      if let pasteView = textView as? PasteAwareTextView {
        pasteView.placeholderLabel.isHidden = textView.text.isEmpty == false
      }
      updateHeight(for: textView)
    }

    func updateHeight(for textView: UITextView) {
      let width = textView.bounds.width
      guard width > 0 else { return }

      textView.layoutIfNeeded()
      let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
      let newHeight = size.height
      guard abs(newHeight - measuredHeight) > 0.5 else { return }
      measuredHeight = newHeight
    }
  }

  final class PasteAwareTextView: UITextView {
    var onPasteImages: (([UIImage]) -> Void)?
    let placeholderLabel = UILabel()
    private var lastKnownWidth: CGFloat = 0

    override init(frame: CGRect, textContainer: NSTextContainer?) {
      super.init(frame: frame, textContainer: textContainer)
      placeholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
      placeholderLabel.textColor = UIColor.label.withAlphaComponent(0.6)
      placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
      addSubview(placeholderLabel)
      NSLayoutConstraint.activate([
        placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
        placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      ])
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()

      let width = bounds.width
      guard width > 0, width != lastKnownWidth else { return }

      lastKnownWidth = width
      textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
      invalidateIntrinsicContentSize()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
      if action == #selector(paste(_:)) {
        if let images = UIPasteboard.general.images, images.isEmpty == false {
          return true
        }
      }
      return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
      if let images = UIPasteboard.general.images, images.isEmpty == false {
        onPasteImages?(images)
        return
      }
      super.paste(sender)
    }
  }
}
#endif

// MARK: - Keyboard helpers

#if os(iOS)
@MainActor
private func dismissKeyboard() {
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
#endif

#if os(macOS)
private struct PromptInputMacTextField: NSViewRepresentable {
  @Binding var text: String
  let placeholder: String
  let onPasteImages: (([NSImage]) -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onPasteImages: onPasteImages)
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
    let onPasteImages: (([NSImage]) -> Void)?

    init(text: Binding<String>, onPasteImages: (([NSImage]) -> Void)?) {
      self._text = text
      self.onPasteImages = onPasteImages
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      text = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      guard commandSelector == #selector(NSText.paste(_:)) else { return false }

      let pasteboard = NSPasteboard.general
      let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] ?? []
      if objects.isEmpty == false {
        onPasteImages?(objects)
        return true
      }
      return false
    }
  }
}
#endif

public struct PromptInputField: View {
  @Binding public var text: String
  public var status: ChatStatus
  public var placeholder: String
  public var attachments: [ChatFilePart]
  public var onPasteImages: (([PlatformImage]) -> Void)?
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

  #if os(iOS)
  @State private var iOSTextViewHeight: CGFloat = 0
  #endif

  public init(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    attachments: [ChatFilePart] = [],
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void
  ) {
    self._text = text
    self.status = status
    self.placeholder = placeholder
    self.attachments = attachments
    self.onPasteImages = onPasteImages
    self.onSend = onSend
    self.onStop = onStop
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if attachments.isEmpty == false {
        attachmentsRow
      }
      composerField
    }
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .disabled(status == .streaming || status == .submitted)
      #if os(iOS)
      .onChange(of: text) { _, newValue in
        if newValue.isEmpty {
          iOSTextViewHeight = 0
        }
      }
      #endif
      #if os(iOS)
      .onChange(of: status) { _, newValue in
        // If the input was focused when we started streaming/submitting, UIKit may restore first responder when
        // the view becomes enabled again. Explicitly dismiss to avoid the keyboard popping back up.
        if newValue == .streaming || newValue == .submitted {
          dismissKeyboard()
        }
      }
      #endif
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
          .foregroundStyle(enabledControlForeground)
          .background { Circle().fill(enabledControlBackground) }
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Stop")
    } else {
      Button {
        let msg = text
        text = ""
        #if os(iOS)
        dismissKeyboard()
        #endif
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

  private var attachmentsRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
          FileAttachmentPreview(attachment: attachment, size: 52, cornerRadius: 10)
        }
      }
      .padding(.leading, 2)
      .padding(.trailing, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var composerField: some View {
    #if os(iOS)
      PromptInputiOSTextField(
        text: $text,
        measuredHeight: $iOSTextViewHeight,
        placeholder: placeholder,
        onPasteImages: onPasteImages
      )
      .font(.body)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: max(iOSTextViewHeight, 22), alignment: .leading)
      .padding(.leading, 6)
    #else
    PromptInputMacTextField(text: $text, placeholder: placeholder, onPasteImages: onPasteImages)
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
        plusButton
        PromptInputField(
          text: configuration.text,
          status: configuration.status,
          placeholder: configuration.placeholder,
          attachments: configuration.attachments,
          onPasteImages: configuration.onPasteImages,
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
    let enabled = configuration.onAdd != nil
    let action = configuration.onAdd ?? {}

    // NOTE: `glassEffect(.clear.interactive(), ...)` can consume touch events when nested in a `Button` label.
    // Use a tap gesture on the glass view itself so it both animates and triggers the action reliably.
    return plusButtonVisual
      .allowsHitTesting(enabled)
      .onTapGesture(perform: action)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel("Add")
      .opacity(enabled ? 1 : 0.45)
  }

  private var plusButtonVisual: some View {
    Image(systemName: "plus")
      .frame(width: plusButtonSize, height: plusButtonSize)
      .font(.system(size: plusButtonIconSize, weight: .medium))
      .foregroundStyle(plusIconColor)
      .glassEffect(.clear.interactive(), in: .circle)
      .contentShape(Circle())
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
  public var attachments: [ChatFilePart]
  public var onPasteImages: (([PlatformImage]) -> Void)?
  public var onSend: (String) -> Void
  public var onStop: () -> Void
  public var onAdd: (() -> Void)?

  @Environment(\.promptInputStyle) private var style

  public init(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    attachments: [ChatFilePart] = [],
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil
  ) {
    self._text = text
    self.status = status
    self.placeholder = placeholder
    self.attachments = attachments
    self.onPasteImages = onPasteImages
    self.onSend = onSend
    self.onStop = onStop
    self.onAdd = onAdd
  }

  public var body: some View {
    style.makeBody(configuration: .init(
      text: $text,
      status: status,
      placeholder: placeholder,
      attachments: attachments,
      onPasteImages: onPasteImages,
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
    attachments: [ChatFilePart] = [],
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
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
      attachments: attachments,
      onPasteImages: onPasteImages,
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
    attachments: [ChatFilePart] = [],
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
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
        attachments: attachments,
        onPasteImages: onPasteImages,
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
  let attachments: [ChatFilePart]
  let onPasteImages: (([PlatformImage]) -> Void)?
  var height: Binding<CGFloat>?
  let showsScrollToLatestButton: Bool
  let overlayPadding: CGFloat
  let onSend: (String) -> Void
  let onStop: () -> Void
  let onAdd: (() -> Void)?

  @State private var measuredHeight: CGFloat = 0
  @State private var isAtLatestForScrollButton: Bool = true
  @State private var scrollToLatestRequest: Int = 0

  func body(content: Content) -> some View {
    let resolvedHeight = height?.wrappedValue ?? measuredHeight
    // Keep placement deterministic: a fixed gap above the composer.
    // (Smaller = closer to the prompt input.)
    let scrollButtonGapAboveComposer: CGFloat = 6
    let scrollButtonBottomPadding = max(0, resolvedHeight + overlayPadding + scrollButtonGapAboveComposer)

    #if os(iOS)
    content
      // Keep the main content (e.g. `Conversation`) extending behind the composer for depth.
      .ignoresSafeArea(.container, edges: .bottom)
      .conversationBottomOverlayHeight(resolvedHeight + overlayPadding)
      .conversationShowsScrollToLatestButton(showsScrollToLatestButton)
      .conversationScrollToLatestRequest($scrollToLatestRequest)
      .onPreferenceChange(ConversationIsAtLatestForScrollButtonPreferenceKey.self) { newValue in
        isAtLatestForScrollButton = newValue
      }
      .safeAreaBar(edge: .bottom) {
        PromptInput(
          text: $text,
          status: status,
          placeholder: placeholder,
          attachments: attachments,
          onPasteImages: onPasteImages,
          onSend: onSend,
          onStop: onStop,
          onAdd: onAdd
        )
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
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
      .overlay(alignment: .bottom) {
        // Suppress during `.submitted` to avoid a brief flash while the conversation is pinning + calibrating
        // reserved tail space immediately after send.
        if showsScrollToLatestButton, isAtLatestForScrollButton == false, status != .submitted {
          Button {
            scrollToLatestRequest += 1
          } label: {
            Image(systemName: "arrow.down")
              .font(.system(size: 13, weight: .semibold))
              .frame(width: 32, height: 32)
              .glassEffect(.clear.interactive(), in: .circle)
              .contentShape(Circle())
              .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 0)
          }
          .buttonStyle(.plain)
          .padding(.bottom, scrollButtonBottomPadding)
          .accessibilityLabel("Scroll to latest")
          .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isAtLatestForScrollButton)
    #else
    content
      .conversationBottomOverlayHeight(resolvedHeight + overlayPadding)
      .conversationShowsScrollToLatestButton(showsScrollToLatestButton)
      .conversationScrollToLatestRequest($scrollToLatestRequest)
      .onPreferenceChange(ConversationIsAtLatestForScrollButtonPreferenceKey.self) { newValue in
        isAtLatestForScrollButton = newValue
      }
      .safeAreaInset(edge: .bottom) {
        PromptInput(
          text: $text,
          status: status,
          placeholder: placeholder,
          attachments: attachments,
          onPasteImages: onPasteImages,
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
      .overlay(alignment: .bottom) {
        if showsScrollToLatestButton, isAtLatestForScrollButton == false, status != .submitted {
          Button {
            scrollToLatestRequest += 1
          } label: {
            Image(systemName: "arrow.down")
              .font(.system(size: 13, weight: .semibold))
              .frame(width: 32, height: 32)
              .glassEffect(.clear.interactive(), in: .circle)
              .contentShape(Circle())
              .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 0)
          }
          .buttonStyle(.plain)
          .padding(.bottom, scrollButtonBottomPadding)
          .accessibilityLabel("Scroll to latest")
          .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isAtLatestForScrollButton)
    #endif
  }

  private func updateMeasuredHeight(_ newHeight: CGFloat) {
    measuredHeight = newHeight
    height?.wrappedValue = newHeight
  }
}

// Height measurement is handled in-place (GeometryReader) to avoid preference propagation issues across `safeAreaInset`.
