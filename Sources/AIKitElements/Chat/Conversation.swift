import SwiftUI
import AIKit

private let conversationBottomSentinelID = "chat-bottom-sentinel"

public struct Conversation<MessageView: View>: View {
  public var messages: [ChatMessage]
  public var status: ChatSessionStatus
  public var bottomOverlayHeight: CGFloat
  @ViewBuilder public var messageView: (ChatMessage) -> MessageView

  @State private var didPerformInitialScroll: Bool = false
  @State private var isAtBottom: Bool = true
  @State private var pendingScrollTask: Task<Void, Never>?

  private let extraBottomPadding: CGFloat = 28
  private let bottomInsetAnimation: Animation = .easeOut(duration: 0.18)
  private let scrollAnimation: Animation = .easeOut(duration: 0.20)
  private let streamingScrollAnimation: Animation = .easeOut(duration: 0.10)
  private let streamingScrollThrottleNanoseconds: UInt64 = 50_000_000

  public init(
    messages: [ChatMessage],
    status: ChatSessionStatus,
    bottomOverlayHeight: CGFloat,
    @ViewBuilder messageView: @escaping (ChatMessage) -> MessageView
  ) {
    self.messages = messages
    self.status = status
    self.bottomOverlayHeight = bottomOverlayHeight
    self.messageView = messageView
  }

  public init(
    messages: [ChatMessage],
    bottomOverlayHeight: CGFloat,
    @ViewBuilder messageView: @escaping (ChatMessage) -> MessageView
  ) {
    self.init(
      messages: messages,
      status: .ready,
      bottomOverlayHeight: bottomOverlayHeight,
      messageView: messageView
    )
  }

  public var body: some View {
      ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(messages) { message in
            messageView(message)
              .id(message.id)
          }

          Color.clear
            .frame(height: bottomInset)
            .animation(bottomInsetAnimation, value: bottomInset)
            .id(conversationBottomSentinelID)
            .onAppear { isAtBottom = true }
            .onDisappear { isAtBottom = false }
        }
        .padding(.top, 20)
      }
      .modifier(ScrollEdgeEffectCompat())
      #if os(iOS)
      .modifier(ScrollDismissesKeyboardCompat())
      #endif
      .onAppear {
        scrollToBottom(proxy, animated: false)
        didPerformInitialScroll = true
      }
      .onChange(of: messages.count) { _ in
        guard didPerformInitialScroll else { return }
        guard isAtBottom else { return }
        scrollToBottom(proxy, animated: true, animation: scrollAnimation)
      }
      .onChange(of: messages) { _ in
        guard status == .streaming else { return }
        guard isAtBottom else { return }
        requestStreamingScroll(proxy)
      }
      .onChange(of: status) { newStatus in
        guard newStatus == .streaming else { return }
        guard isAtBottom else { return }
        requestStreamingScroll(proxy)
      }
      .onChange(of: bottomInset) { _ in
        guard isAtBottom else { return }
        scrollToBottom(proxy, animated: true, animation: scrollAnimation)
      }
    }
  }

  private var bottomInset: CGFloat {
    max(1, bottomOverlayHeight + extraBottomPadding)
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
    } else if let lastID = messages.last?.id {
      targetID = lastID
    } else {
      targetID = conversationBottomSentinelID
    }

    if animated {
      withAnimation(animation) {
        proxy.scrollTo(targetID, anchor: .bottom)
      }
    } else {
      proxy.scrollTo(targetID, anchor: .bottom)
    }
  }
}

private struct ScrollEdgeEffectCompat: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content.scrollEdgeEffectStyle(.hard, for: .bottom)
    } else {
      content
    }
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

public struct ConversationContent<Content: View>: View {
  public var spacing: CGFloat
  public var padding: EdgeInsets
  @ViewBuilder public var content: () -> Content

  public init(
    spacing: CGFloat = 32,
    padding: EdgeInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16),
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.spacing = spacing
    self.padding = padding
    self.content = content
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      content()
    }
    .padding(padding)
  }
}

public struct ConversationEmptyState<Content: View>: View {
  public var title: String
  public var description: String?
  public var icon: AnyView?
  @ViewBuilder public var content: () -> Content

  public init(
    title: String = "No messages yet",
    description: String? = "Start a conversation to see messages here",
    icon: AnyView? = nil,
    @ViewBuilder content: @escaping () -> Content = { EmptyView() }
  ) {
    self.title = title
    self.description = description
    self.icon = icon
    self.content = content
  }

  public var body: some View {
    VStack(spacing: 12) {
      if let icon {
        icon
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 4) {
        Text(title)
          .font(.subheadline.weight(.medium))

        if let description {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }

      content()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(32)
    .multilineTextAlignment(.center)
  }
}

// ConversationScrollButton is currently handled inside Conversation, mirroring ../Assistant behavior.
