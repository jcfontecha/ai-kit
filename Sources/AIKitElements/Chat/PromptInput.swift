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
  let maxVisibleLines: Int
  let focusRequestID: Int
  let onPasteImages: (([UIImage]) -> Void)?
  let onEditingChanged: ((Bool) -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(
      text: $text,
      measuredHeight: $measuredHeight,
      maxVisibleLines: maxVisibleLines,
      onPasteImages: onPasteImages,
      onEditingChanged: onEditingChanged
    )
  }

  func makeUIView(context: Context) -> UITextView {
    let view = PasteAwareTextView()
    view.text = text
    view.backgroundColor = .clear
    view.clipsToBounds = true
    view.font = UIFont.preferredFont(forTextStyle: .body)
    view.delegate = context.coordinator
    view.isScrollEnabled = false
    view.showsVerticalScrollIndicator = false
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.textContainer.lineBreakMode = .byWordWrapping
    view.textContainer.widthTracksTextView = true
    view.onPasteImages = context.coordinator.onPasteImages
    view.placeholderLabel.text = placeholder
    view.placeholderLabel.isHidden = text.isEmpty == false
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)

    context.coordinator.lastTextViewText = view.text
    context.coordinator.updateHeight(for: view)
    return view
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    if uiView.text != text {
      // Avoid clobbering the user's caret position when SwiftUI propagates changes back into UIKit.
      // This is especially noticeable for multi-line edits where the selection can jump to the end.
      let wasFirstResponder = uiView.isFirstResponder
      let hadMarkedText = (uiView.markedTextRange != nil)

      // If the user is actively composing with an IME, don't rewrite the entire text.
      // Doing so can cancel the marked text session and move the insertion point.
      //
      // Additionally: avoid rewriting `uiView.text` during normal typing. SwiftUI can call `updateUIView`
      // while UIKit is still finalizing selection changes (notably after Return). Writing text and then
      // restoring a stale selection can leave the caret "behind" the inserted newline.
      if wasFirstResponder, hadMarkedText == false, uiView.text == context.coordinator.lastTextViewText {
        // No-op: this update is just reflecting the user's typing; let UIKit own the text/selection.
      } else if wasFirstResponder == false || hadMarkedText == false {
        let previousSelection = uiView.selectedRange
        uiView.text = text
        context.coordinator.lastTextViewText = text

        if wasFirstResponder {
          let utf16Length = (uiView.text as NSString).length
          let clampedLocation = min(previousSelection.location, utf16Length)
          let clampedLength = min(previousSelection.length, max(0, utf16Length - clampedLocation))
          uiView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
        }
      }
    }
    if let pasteView = uiView as? PasteAwareTextView {
      pasteView.onPasteImages = context.coordinator.onPasteImages
    }
    if let pasteView = uiView as? PasteAwareTextView {
      pasteView.placeholderLabel.text = placeholder
      pasteView.placeholderLabel.isHidden = uiView.text.isEmpty == false
    }

    context.coordinator.updateHeight(for: uiView)
    DispatchQueue.main.async {
      context.coordinator.updateHeight(for: uiView)
    }

    if focusRequestID > 0, focusRequestID != context.coordinator.lastFocusRequestID {
      context.coordinator.lastFocusRequestID = focusRequestID
      DispatchQueue.main.async {
        guard uiView.window != nil else { return }
        // Only move the insertion point when we *actually* take focus.
        // If the user already placed the caret (e.g. editing in the middle of the message),
        // don't override their selection.
        guard uiView.isFirstResponder == false else { return }
        uiView.becomeFirstResponder()
        uiView.selectedRange = NSRange(location: (uiView.text as NSString).length, length: 0)
      }
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize {
    let targetWidth = proposal.width ?? uiView.bounds.width
    let resolvedWidth = max(0, targetWidth)
    context.coordinator.lastProposedWidth = resolvedWidth

    uiView.layoutIfNeeded()
    let size = uiView.sizeThatFits(CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude))
    return CGSize(width: resolvedWidth, height: size.height)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    @Binding private var text: String
    @Binding private var measuredHeight: CGFloat
    private let maxVisibleLines: Int
    let onPasteImages: (([UIImage]) -> Void)?
    let onEditingChanged: ((Bool) -> Void)?
    var lastProposedWidth: CGFloat = 0
    var lastFocusRequestID: Int = 0
    var lastTextViewText: String = ""
    private var pendingCaretAfterNewline: NSRange?

    init(
      text: Binding<String>,
      measuredHeight: Binding<CGFloat>,
      maxVisibleLines: Int,
      onPasteImages: (([UIImage]) -> Void)?,
      onEditingChanged: ((Bool) -> Void)?
    ) {
      self._text = text
      self._measuredHeight = measuredHeight
      self.maxVisibleLines = maxVisibleLines
      self.onPasteImages = onPasteImages
      self.onEditingChanged = onEditingChanged
    }

    func textViewDidChange(_ textView: UITextView) {
      lastTextViewText = textView.text
      text = textView.text
      if let pasteView = textView as? PasteAwareTextView {
        pasteView.placeholderLabel.isHidden = textView.text.isEmpty == false
      }
      updateHeight(for: textView)

      if let pending = pendingCaretAfterNewline {
        pendingCaretAfterNewline = nil
        DispatchQueue.main.async {
          let hasMarkedText = (textView.markedTextRange != nil)
          guard textView.isFirstResponder, hasMarkedText == false else { return }

          let utf16Length = (textView.text as NSString).length
          let clampedLocation = min(pending.location, utf16Length)
          textView.selectedRange = NSRange(location: clampedLocation, length: 0)

          // When the text view is in "expanding" mode (`isScrollEnabled == false`), `scrollRangeToVisible`
          // can temporarily push `contentOffset` while SwiftUI is still updating the view height. That leaves
          // the text visually shifted upward even after the container grows.
          if textView.isScrollEnabled {
            textView.scrollRangeToVisible(textView.selectedRange)
          } else {
            textView.setContentOffset(.zero, animated: false)
          }
        }
      }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
      // Hitting return can race layout/height updates; in some cases the selection doesn't advance reliably and
      // subsequent typing inserts before the newline. Record the expected post-insert caret and apply it once the
      // text change has landed.
      if text == "\n" {
        pendingCaretAfterNewline = NSRange(location: range.location + 1, length: 0)
      }
      return true
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      onEditingChanged?(true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      onEditingChanged?(false)
    }

    func updateHeight(for textView: UITextView) {
      let width = (textView.bounds.width > 0) ? textView.bounds.width : lastProposedWidth
      guard width > 0 else { return }

      textView.layoutIfNeeded()
      let contentSize = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))

      // Cap the visible height to keep the composer from growing too tall.
      let lineHeight = textView.font?.lineHeight ?? 17
      let maxHeight = ceil(lineHeight * CGFloat(max(1, maxVisibleLines)))
      let clampedHeight = min(contentSize.height, maxHeight)

      // Allow internal scrolling only once we exceed the max height.
      let shouldScroll = contentSize.height > (maxHeight + 0.5)
      if textView.isScrollEnabled != shouldScroll {
        let wasScrollEnabled = textView.isScrollEnabled
        textView.isScrollEnabled = shouldScroll
        textView.showsVerticalScrollIndicator = shouldScroll

        if wasScrollEnabled, shouldScroll == false {
          textView.setContentOffset(.zero, animated: false)
        }
      }

      if shouldScroll == false, abs(textView.contentOffset.y) > 0.5 {
        textView.setContentOffset(.zero, animated: false)
      }

      guard abs(clampedHeight - measuredHeight) > 0.5 else { return }
      measuredHeight = clampedHeight
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
  let focusRequestID: Int
  let onPasteImages: (([NSImage]) -> Void)?
  let onEditingChanged: ((Bool) -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onPasteImages: onPasteImages, onEditingChanged: onEditingChanged)
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

    if focusRequestID > 0, focusRequestID != context.coordinator.lastFocusRequestID {
      context.coordinator.lastFocusRequestID = focusRequestID
      DispatchQueue.main.async {
        guard nsView.window != nil else { return }
        nsView.window?.makeFirstResponder(nsView)
      }
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    @Binding private var text: String
    let onPasteImages: (([NSImage]) -> Void)?
    let onEditingChanged: ((Bool) -> Void)?
    var lastFocusRequestID: Int = 0

    init(
      text: Binding<String>,
      onPasteImages: (([NSImage]) -> Void)?,
      onEditingChanged: ((Bool) -> Void)?
    ) {
      self._text = text
      self.onPasteImages = onPasteImages
      self.onEditingChanged = onEditingChanged
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
      onEditingChanged?(true)
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      text = field.stringValue
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      onEditingChanged?(false)
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
  public var editing: PromptInputEditingContext?
  public var expandedBottomBar: AnyView?
  public var onPasteImages: (([PlatformImage]) -> Void)?
  public var onSend: (String) -> Void
  public var onStop: () -> Void

  @Environment(\.chatSheetDetentSelection) private var chatSheetDetentSelection
  @Environment(\.chatSheetSupportedDetents) private var chatSheetSupportedDetents
  @Environment(\.chatSheetKeepsExpandedOnSend) private var chatSheetKeepsExpandedOnSend

  // Tuning knobs
  private let pillContentLeadingPadding: CGFloat = 10
  private let pillContentVerticalPadding: CGFloat = 12
  private let pillToControlPadding: CGFloat = 8
  private let trailingControlInset: CGFloat = 6
  private let controlSize: CGFloat = 30
  private let controlIconSize: CGFloat = 16
  private var controlIconPadding: CGFloat { (controlSize - controlIconSize) / 2 }
  private let focusDelay: Duration = .milliseconds(350)

  #if os(iOS)
  @State private var iOSTextViewHeight: CGFloat = 0
  #endif
  @State private var focusRequestID: Int = 0
  @State private var focusTask: Task<Void, Never>?
  @State private var isFocused: Bool = false

  public init(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    attachments: [ChatFilePart] = [],
    editing: PromptInputEditingContext? = nil,
    expandedBottomBar: AnyView? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void
  ) {
    self._text = text
    self.status = status
    self.placeholder = placeholder
    self.attachments = attachments
    self.editing = editing
    self.expandedBottomBar = expandedBottomBar
    self.onPasteImages = onPasteImages
    self.onSend = onSend
    self.onStop = onStop
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let editing {
        editingRow(editing)
          .offset(y: 2)
          .padding(.trailing, -(trailingControlWidth + trailingControlInset) + 18)
      }
      if attachments.isEmpty == false {
        attachmentsRow
      }
      composerField
      if isFocused, let expandedBottomBar {
        expandedBottomBar
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, expandedBottomBarLeadingInsetAdjustment)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .disabled(status == .streaming || status == .submitted)
      .onAppear {
        if editing != nil {
          scheduleFocus()
        } else {
          focusRequestID = 0
        }
      }
      .onChange(of: editing != nil) { _, newValue in
        if newValue {
          scheduleFocus()
        } else {
          focusTask?.cancel()
          focusTask = nil
          focusRequestID = 0
          withAnimation(expandedBottomBarAnimation) {
            isFocused = false
          }
          #if os(iOS)
          dismissKeyboard()
          #endif
        }
      }
      .onDisappear {
        focusTask?.cancel()
        focusTask = nil
        focusRequestID = 0
        withAnimation(expandedBottomBarAnimation) {
          isFocused = false
        }
      }
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
      .padding(.top, pillContentVerticalPadding)
      .padding(.bottom, pillContentBottomPadding)
      .overlay(alignment: .bottomTrailing) {
        trailingControl
          .padding([.trailing, .top, .bottom], pillToControlPadding)
      }
  }

  private func scheduleFocus() {
    focusTask?.cancel()
    focusTask = Task { @MainActor in
      try? await Task.sleep(for: focusDelay)
      guard Task.isCancelled == false else { return }
      focusRequestID += 1
    }
  }

  private var sendEnabled: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || attachments.isEmpty == false
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
    } else if let editing {
      Button {
        let msg = text
        text = ""
        #if os(iOS)
        keepChatSheetExpandedIfConfigured()
        dismissKeyboard()
        #endif
        editing.onCommit(msg)
      } label: {
        Image(systemName: "checkmark")
          .frame(width: controlIconSize, height: controlIconSize)
          .padding(controlIconPadding)
          .foregroundStyle(enabledControlForeground)
          .background { Circle().fill(enabledControlBackground) }
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(sendEnabled == false)
      .accessibilityLabel("Update message")
    } else {
      Button {
        let msg = text
        text = ""
        #if os(iOS)
        keepChatSheetExpandedIfConfigured()
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

  private func keepChatSheetExpandedIfConfigured() {
    guard chatSheetKeepsExpandedOnSend else { return }
    guard chatSheetSupportedDetents.contains(.large) else { return }
    chatSheetDetentSelection?.wrappedValue = .large
  }

  private func editingRow(_ editing: PromptInputEditingContext) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(editing.title)
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer(minLength: 0)

      Button("Cancel") {
        editing.onCancel()
      }
      .buttonStyle(.plain)
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Cancel editing")
    }
    .padding(.leading, 6)
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
        maxVisibleLines: 8,
        focusRequestID: focusRequestID,
        onPasteImages: onPasteImages,
        onEditingChanged: { isEditing in
          withAnimation(expandedBottomBarAnimation) {
            isFocused = isEditing
          }
          guard isEditing else { return }
          keepChatSheetExpandedIfConfigured()
        }
      )
      .font(.body)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(
        height: max(
          iOSTextViewHeight,
          ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight)
        ),
        alignment: .leading
      )
      .padding(.leading, 6)
    #else
    PromptInputMacTextField(
      text: $text,
      placeholder: placeholder,
      focusRequestID: focusRequestID,
      onPasteImages: onPasteImages,
      onEditingChanged: { isEditing in
        withAnimation(expandedBottomBarAnimation) {
          isFocused = isEditing
        }
      }
    )
    #endif
  }

  private var expandedBottomBarAnimation: Animation? {
    guard expandedBottomBar != nil else { return nil }
    return .easeOut(duration: expandedBottomBarAnimationDuration)
  }

  private var expandedBottomBarAnimationDuration: CGFloat {
    #if os(iOS)
    0.22
    #else
    0.22
    #endif
  }

  private var expandedBottomBarLeadingInsetAdjustment: CGFloat {
    // Keep the leading buttons inset consistent with the trailing send/stop button inset.
    pillToControlPadding - pillContentLeadingPadding
  }

  private var pillContentBottomPadding: CGFloat {
    // When the expanded bottom bar is visible, align its bottom inset with the send/stop control inset.
    if expandedBottomBar != nil, isFocused {
      return pillToControlPadding
    }
    return pillContentVerticalPadding
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
          editing: configuration.editing,
          expandedBottomBar: configuration.expandedBottomBar,
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
  public var editing: PromptInputEditingContext?
  public var expandedBottomBar: AnyView?
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
    editing: PromptInputEditingContext? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil,
    expandedBottomBar: AnyView? = nil
  ) {
    self._text = text
    self.status = status
    self.placeholder = placeholder
    self.attachments = attachments
    self.editing = editing
    self.expandedBottomBar = expandedBottomBar
    self.onPasteImages = onPasteImages
    self.onSend = onSend
    self.onStop = onStop
    self.onAdd = onAdd
  }

  public init<ExpandedBottomBar: View>(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    attachments: [ChatFilePart] = [],
    editing: PromptInputEditingContext? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil,
    @ViewBuilder expandedBottomBar: () -> ExpandedBottomBar
  ) {
    self.init(
      text: text,
      status: status,
      placeholder: placeholder,
      attachments: attachments,
      editing: editing,
      onPasteImages: onPasteImages,
      onSend: onSend,
      onStop: onStop,
      onAdd: onAdd,
      expandedBottomBar: AnyView(expandedBottomBar())
    )
  }

  public var body: some View {
    style.makeBody(configuration: .init(
      text: $text,
      status: status,
      placeholder: placeholder,
      attachments: attachments,
      editing: editing,
      expandedBottomBar: expandedBottomBar,
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
    editing: PromptInputEditingContext? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    showsScrollToLatestButton: Bool = true,
    overlayPadding: CGFloat = 8,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil,
    expandedBottomBar: AnyView? = nil
  ) -> some View {
    modifier(ChatComposerModifier(
      text: text,
      status: status,
      placeholder: placeholder,
      attachments: attachments,
      editing: editing,
      onPasteImages: onPasteImages,
      height: nil,
      showsScrollToLatestButton: showsScrollToLatestButton,
      overlayPadding: overlayPadding,
      onSend: onSend,
      onStop: onStop,
      onAdd: onAdd,
      expandedBottomBar: expandedBottomBar
    ))
  }

  func chatComposer<ExpandedBottomBar: View>(
    text: Binding<String>,
    status: ChatStatus,
    placeholder: String = "Message",
    attachments: [ChatFilePart] = [],
    editing: PromptInputEditingContext? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    showsScrollToLatestButton: Bool = true,
    overlayPadding: CGFloat = 8,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil,
    @ViewBuilder expandedBottomBar: () -> ExpandedBottomBar
  ) -> some View {
    chatComposer(
      text: text,
      status: status,
      placeholder: placeholder,
      attachments: attachments,
      editing: editing,
      onPasteImages: onPasteImages,
      showsScrollToLatestButton: showsScrollToLatestButton,
      overlayPadding: overlayPadding,
      onSend: onSend,
      onStop: onStop,
      onAdd: onAdd,
      expandedBottomBar: AnyView(expandedBottomBar())
    )
  }

  func promptInputBottomBar(
    text: Binding<String>,
    status: ChatStatus,
    attachments: [ChatFilePart] = [],
    editing: PromptInputEditingContext? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    height: Binding<CGFloat>,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil,
    expandedBottomBar: AnyView? = nil
  ) -> some View {
    modifier(
      ChatComposerModifier(
        text: text,
        status: status,
        placeholder: "Message",
        attachments: attachments,
        editing: editing,
        onPasteImages: onPasteImages,
        height: height,
        showsScrollToLatestButton: false,
        overlayPadding: 0,
        onSend: onSend,
        onStop: onStop,
        onAdd: onAdd,
        expandedBottomBar: expandedBottomBar
      )
    )
  }

  func promptInputBottomBar<ExpandedBottomBar: View>(
    text: Binding<String>,
    status: ChatStatus,
    attachments: [ChatFilePart] = [],
    editing: PromptInputEditingContext? = nil,
    onPasteImages: (([PlatformImage]) -> Void)? = nil,
    height: Binding<CGFloat>,
    onSend: @escaping (String) -> Void,
    onStop: @escaping () -> Void,
    onAdd: (() -> Void)? = nil,
    @ViewBuilder expandedBottomBar: () -> ExpandedBottomBar
  ) -> some View {
    promptInputBottomBar(
      text: text,
      status: status,
      attachments: attachments,
      editing: editing,
      onPasteImages: onPasteImages,
      height: height,
      onSend: onSend,
      onStop: onStop,
      onAdd: onAdd,
      expandedBottomBar: AnyView(expandedBottomBar())
    )
  }
}

private struct ChatComposerModifier: ViewModifier {
  @Binding var text: String
  let status: ChatStatus
  let placeholder: String
  let attachments: [ChatFilePart]
  let editing: PromptInputEditingContext?
  let onPasteImages: (([PlatformImage]) -> Void)?
  var height: Binding<CGFloat>?
  let showsScrollToLatestButton: Bool
  let overlayPadding: CGFloat
  let onSend: (String) -> Void
  let onStop: () -> Void
  let onAdd: (() -> Void)?
  let expandedBottomBar: AnyView?

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
          editing: editing,
          onPasteImages: onPasteImages,
          onSend: onSend,
          onStop: onStop,
          onAdd: onAdd,
          expandedBottomBar: expandedBottomBar
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
          editing: editing,
          onPasteImages: onPasteImages,
          onSend: onSend,
          onStop: onStop,
          onAdd: onAdd,
          expandedBottomBar: expandedBottomBar
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
