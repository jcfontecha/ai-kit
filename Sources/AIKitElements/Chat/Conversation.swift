import SwiftUI
import AIKit

private let conversationBottomSentinelID = "chat-bottom-sentinel"
private let conversationTopSentinelID = "chat-top-sentinel"
private let conversationMessagePageSize = 60

public struct Conversation<MessageView: View>: View {
  public var messages: [ChatMessage]
  public var status: ChatStatus
  @ViewBuilder public var messageView: (ChatMessage) -> MessageView

  @Environment(\.chatTheme) private var theme
  @Environment(\.conversationBottomOverlayHeight) private var bottomOverlayHeight
  @Environment(\.conversationShowsScrollButton) private var showsScrollButton

  @State private var visibleCount: Int = conversationMessagePageSize
  @State private var didPerformInitialScroll: Bool = false
  @State private var isAtBottom: Bool = true
  @State private var pendingScrollTask: Task<Void, Never>?
  @State private var scrollPosition: String? = conversationBottomSentinelID

  private let extraBottomPadding: CGFloat = 0
  private let bottomInsetAnimation: Animation = .easeOut(duration: 0.18)
  private let scrollAnimation: Animation = .easeOut(duration: 0.20)
  private let streamingScrollAnimation: Animation = .easeOut(duration: 0.10)
  private let streamingScrollThrottleNanoseconds: UInt64 = 50_000_000

  public init(
    messages: [ChatMessage],
    status: ChatStatus = .ready,
    @ViewBuilder messageView: @escaping (ChatMessage) -> MessageView
  ) {
    self.messages = messages
    self.status = status
    self.messageView = messageView
  }

  public init(
    messages: [ChatMessage],
    status: ChatStatus = .ready
  ) where MessageView == AnyView {
    self.init(messages: messages, status: status) { message in
      AnyView(Self.defaultMessageView(message: message))
    }
  }

  public var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: theme.spacing.messageRow) {
          if shouldShowLoadMoreSentinel {
            Color.clear
              .frame(height: 1)
              .id(conversationTopSentinelID)
              .onAppear {
                loadOlderMessages(with: proxy)
              }
          }

          ForEach(Array(visibleMessages)) { message in
            messageView(message)
              .id(message.id)
          }

          Color.clear
            .frame(height: bottomInset)
            .animation(bottomInsetAnimation, value: bottomInset)
            .id(conversationBottomSentinelID)
        }
        .padding(theme.spacing.contentPadding)
        .scrollTargetLayout()
      }
      .scrollPosition(id: $scrollPosition, anchor: .bottom)
      .modifier(ScrollEdgeEffectCompat())
      .defaultScrollAnchor(.bottom)
      #if os(iOS)
      .modifier(ScrollDismissesKeyboardCompat())
      #endif
      .onAppear {
        syncVisibleCountWithMessages()
        scrollToBottom(proxy, animated: false)
        scrollPosition = conversationBottomSentinelID
        didPerformInitialScroll = true
      }
      .onChange(of: scrollPosition) {
        isAtBottom = scrollPosition == conversationBottomSentinelID
      }
      .onChange(of: messages.count) {
        syncVisibleCountWithMessages()
        guard didPerformInitialScroll else { return }
        guard isAtBottom else { return }
        scrollToBottom(proxy, animated: true, animation: scrollAnimation)
      }
      .onChange(of: messages) {
        guard status == .streaming else { return }
        guard isAtBottom else { return }
        requestStreamingScroll(proxy)
      }
      .onChange(of: status) {
        let newStatus = status
        guard newStatus == .streaming else { return }
        guard isAtBottom else { return }
        requestStreamingScroll(proxy)
      }
      .onChange(of: bottomInset) {
        guard isAtBottom else { return }
        scrollToBottom(proxy, animated: true, animation: scrollAnimation)
      }
      .overlay(alignment: .bottom) {
        if showsScrollButton, isAtBottom == false {
          Button {
            scrollToBottom(proxy, animated: true, animation: scrollAnimation)
          } label: {
            Image(systemName: "arrow.down")
              .font(.system(size: 13, weight: .semibold))
              .frame(width: 32, height: 32)
              .glassEffect(.clear.interactive(), in: .circle)
              .contentShape(Circle())
              .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 0)
          }
          .buttonStyle(.plain)
          .padding(.bottom, 12)
          .accessibilityLabel("Scroll to latest")
          .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isAtBottom)
    }
  }

  private var bottomInset: CGFloat {
    max(1, extraBottomPadding + bottomOverlayHeight)
  }

  private var displayMessages: [ChatMessage] {
    messages.filter { $0.role != .system }
  }

  private var resolvedVisibleCount: Int {
    guard displayMessages.isEmpty == false else { return 0 }
    let baseline = min(conversationMessagePageSize, displayMessages.count)
    let desired = max(visibleCount, baseline)
    return min(desired, displayMessages.count)
  }

  private var visibleMessages: ArraySlice<ChatMessage> {
    displayMessages.suffix(resolvedVisibleCount)
  }

  private var shouldShowLoadMoreSentinel: Bool {
    resolvedVisibleCount < displayMessages.count
  }

  private func syncVisibleCountWithMessages() {
    guard displayMessages.isEmpty == false else {
      if visibleCount != 0 {
        visibleCount = 0
      }
      didPerformInitialScroll = false
      return
    }

    let baseline = min(conversationMessagePageSize, displayMessages.count)
    if visibleCount < baseline {
      visibleCount = baseline
    } else if visibleCount > displayMessages.count {
      visibleCount = displayMessages.count
    }
  }

  private func loadOlderMessages(with proxy: ScrollViewProxy) {
    guard didPerformInitialScroll else { return }
    guard visibleCount < displayMessages.count else { return }

    let currentFirstID = visibleMessages.first?.id
    let newCount = min(displayMessages.count, visibleCount + conversationMessagePageSize)
    guard newCount != visibleCount else { return }

    visibleCount = newCount

    if let currentFirstID {
      DispatchQueue.main.async {
        proxy.scrollTo(currentFirstID, anchor: .top)
      }
    }
  }

  private func requestStreamingScroll(_ proxy: ScrollViewProxy) {
    guard pendingScrollTask == nil else { return }
    pendingScrollTask = Task { @MainActor in
      defer { pendingScrollTask = nil }
      try? await Task.sleep(nanoseconds: streamingScrollThrottleNanoseconds)
      guard isAtBottom else { return }
      scrollToBottom(proxy, animated: true, animation: streamingScrollAnimation)
    }
  }

  private func scrollToBottom(
    _ proxy: ScrollViewProxy,
    animated: Bool,
    animation: Animation = .easeOut(duration: 0.2)
  ) {
    let targetID: String
    if bottomInset > 0 {
      targetID = conversationBottomSentinelID
    } else if let lastID = displayMessages.last?.id {
      targetID = lastID
    } else {
      targetID = conversationBottomSentinelID
    }

    if animated {
      withAnimation(animation) {
        scrollPosition = targetID
        proxy.scrollTo(targetID, anchor: .bottom)
      }
    } else {
      scrollPosition = targetID
      proxy.scrollTo(targetID, anchor: .bottom)
    }
  }

  @ViewBuilder
  private static func defaultMessageView(message: ChatMessage) -> some View {
    switch message.role {
    case .user:
      HStack(alignment: .top) {
        Spacer(minLength: 24)
        VStack(alignment: .trailing, spacing: 8) {
          if userAttachments(message).isEmpty == false {
            FileAttachmentPreviewRow(attachments: userAttachments(message), alignment: .trailing)
          }
          if userText(message).isEmpty == false {
            UserBubble(text: userText(message))
          }
        }
      }

    case .assistant:
      HStack(alignment: .top) {
        AssistantMessage(messageID: message.id, parts: message.parts)
      }

    case .system:
      Text(messageText(message))
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

    case .tool:
      Text("Tool role message")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

    @unknown default:
      Text("Unsupported role: \(message.role.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private static func messageText(_ message: ChatMessage) -> String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private static func userText(_ message: ChatMessage) -> String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private static func userAttachments(_ message: ChatMessage) -> [ChatFilePart] {
    message.parts.compactMap { part in
      guard case let .file(file) = part else { return nil }
      return file
    }
  }
}

private struct ScrollEdgeEffectCompat: ViewModifier {
  func body(content: Content) -> some View {
    content.scrollEdgeEffectStyle(.soft, for: .bottom)
  }
}

#if os(iOS)
private struct ScrollDismissesKeyboardCompat: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollDismissesKeyboard(.interactively)
    } else {
      content
    }
  }
}
#endif
