import SwiftUI
import AIKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let conversationBottomSentinelID = ConversationScrollConstants.bottomSentinelID
private let conversationReservedTailSentinelID = ConversationScrollConstants.reservedTailSentinelID
private let conversationTopSentinelID = ConversationScrollConstants.topSentinelID
private let conversationMessagePageSize = ConversationScrollConstants.messagePageSize
private let conversationScrollCoordinateSpaceName = ConversationScrollConstants.scrollCoordinateSpaceName

private struct BottomSentinelMaxYPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = -1
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    let next = nextValue()
    if next >= 0 {
      value = next
    }
  }
}

private struct TailSentinelMaxYPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = -1
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    let next = nextValue()
    if next >= 0 {
      value = next
    }
  }
}

public struct Conversation<MessageView: View>: View {
  public var messages: [ChatMessage]
  public var status: ChatStatus
  public var sendTrigger: Int
  @ViewBuilder public var messageView: (ChatMessage) -> MessageView

  @Environment(\.chatTheme) private var theme
  @Environment(\.conversationBottomOverlayHeight) private var bottomOverlayHeight
  @Environment(\.conversationShowsScrollButton) private var showsScrollButton
  @Environment(\.conversationAnchorsNewUserMessagesToTop) private var anchorsNewUserMessagesToTop
  @Environment(\.conversationDebugOverlayEnabled) private var debugOverlayEnabled
  @Environment(\.conversationScrollToLatestRequest) private var scrollToLatestRequest

  @StateObject private var scrollModel = ConversationScrollViewModel()
  @State private var streamingFollowTask: Task<Void, Never>?
  @State private var pendingTailUpdateTask: Task<Void, Never>?
  @State private var didCopyDebugState: Bool = false

  private let bottomInsetAnimation: Animation = .easeOut(duration: 0.18)
  private let scrollAnimation: Animation = .easeOut(duration: 0.20)
  private let streamingScrollAnimation: Animation = .easeOut(duration: 0.10)
  private let streamingScrollThrottleNanoseconds: UInt64 = 50_000_000
  private let tailUpdateThrottleNanoseconds: UInt64 = 50_000_000

  public init(
    messages: [ChatMessage],
    status: ChatStatus = .ready,
    sendTrigger: Int = 0,
    @ViewBuilder messageView: @escaping (ChatMessage) -> MessageView
  ) {
    self.messages = messages
    self.status = status
    self.sendTrigger = sendTrigger
    self.messageView = messageView
  }

  public init(
    messages: [ChatMessage],
    status: ChatStatus = .ready
  ) where MessageView == AnyView {
    self.init(messages: messages, status: status, sendTrigger: 0)
  }

  public init(
    messages: [ChatMessage],
    status: ChatStatus = .ready,
    sendTrigger: Int = 0
  ) where MessageView == AnyView {
    self.init(messages: messages, status: status, sendTrigger: sendTrigger) { message in
      AnyView(DefaultMessageView(message: message))
    }
  }

  public var body: some View {
    let displayMessages = Self.filteredDisplayMessages(messages)
    let visibleMessages = scrollModel.visibleMessages(displayMessages: displayMessages)

    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          LazyVStack(alignment: .leading, spacing: theme.spacing.messageRow) {
            if scrollModel.shouldShowLoadMoreSentinel(displayMessages: displayMessages) {
              Color.clear
                .frame(height: 1)
                .id(conversationTopSentinelID)
                .onAppear {
                  let steps = scrollModel.handleLoadOlderMessages(
                    displayMessages: displayMessages,
                    currentFirstVisibleID: scrollModel.visibleMessages(displayMessages: displayMessages).first?.id
                  )
                  executeScrollSteps(steps, proxy: proxy)
                }
            }

            ForEach(visibleMessages) { message in
              if scrollModel.shouldMeasureMessageHeights {
                messageView(message)
                  .id(message.id)
                  .background(measureHeight(id: message.id))
              } else {
                messageView(message)
                  .id(message.id)
              }
            }
          }

          bottomSentinelView

          if scrollModel.reservedTailSpace > 0 {
            // Tail spacer creates scroll range so the newest user message can be pinned to the top.
            Color.clear
              .frame(height: scrollModel.reservedTailSpace)
              .animation(bottomInsetAnimation, value: scrollModel.reservedTailSpace)

            // A 1pt sentinel at the very end so "at bottom" detection isn't delayed by the spacer height.
            Color.clear
              .frame(height: 1)
              .background {
                GeometryReader { proxy in
                  Color.clear.preference(
                    key: TailSentinelMaxYPreferenceKey.self,
                    value: proxy.frame(in: .named(conversationScrollCoordinateSpaceName)).maxY
                  )
                }
              }
              .id(conversationReservedTailSentinelID)
              .onAppear {
                scrollModel.updateTailSentinelVisibility(isVisible: true)
              }
              .onDisappear {
                scrollModel.updateTailSentinelVisibility(isVisible: false)
              }
          }
        }
        .padding(theme.spacing.contentPadding)
        .scrollTargetLayout()
      }
      .coordinateSpace(name: conversationScrollCoordinateSpaceName)
      #if os(iOS)
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screenHeight = UIScreen.main.bounds.height
        let overlap = max(0, screenHeight - endFrame.minY)
        scrollModel.updateKeyboardHeightIfNeeded(overlap)
      }
      #endif
      .simultaneousGesture(
        DragGesture(minimumDistance: 2).onChanged { _ in
          guard status == .streaming else { return }
          stopStreamingFollow()
        }
      )
      .onPreferenceChange(MessageHeightsPreferenceKey.self) { heights in
        scrollModel.ingestMessageHeights(heights)
        scheduleTailUpdate(proxy: proxy)
      }
      .onPreferenceChange(BottomSentinelMaxYPreferenceKey.self) { maxY in
        scrollModel.updateBottomSentinelMaxY(maxY)
      }
      .onPreferenceChange(TailSentinelMaxYPreferenceKey.self) { maxY in
        scrollModel.updateTailSentinelMaxY(maxY)
        // Only schedule a tail update when we're waiting for the tail sentinel to become measurable for the
        // initial send-anchoring plan. Scheduling on every maxY change causes feedback loops during scrolling.
        if scrollModel.pendingSendAnchoringMessageID != nil {
          scheduleTailUpdate(proxy: proxy)
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .onAppear {
              guard shouldMeasureViewport else { return }
              scrollModel.updateViewportHeightIfNeeded(geo.size.height)
              scheduleTailUpdate(proxy: proxy)
            }
            .onChange(of: geo.size.height) { _, newHeight in
              guard shouldMeasureViewport else { return }
              scrollModel.updateViewportHeightIfNeeded(newHeight)
              scheduleTailUpdate(proxy: proxy)
            }
        }
      }
      .scrollPosition(id: $scrollModel.scrollPosition, anchor: .bottom)
      .modifier(ScrollEdgeEffectCompat())
      .defaultScrollAnchor(.bottom)
      #if os(iOS)
      .modifier(ScrollDismissesKeyboardCompat())
      #endif
      .onAppear {
        scrollModel.updateBottomOverlayHeight(bottomOverlayHeight)
        let steps = scrollModel.handleOnAppear(displayMessages: displayMessages)
        executeScrollSteps(steps, proxy: proxy)
        startStreamingFollowIfNeeded()
      }
      .onDisappear {
        stopStreamingFollow()
        pendingTailUpdateTask?.cancel()
        pendingTailUpdateTask = nil
      }
      .onChange(of: bottomOverlayHeight) { _, newValue in
        scrollModel.updateBottomOverlayHeight(newValue)
        let steps = scrollModel.handleBottomInsetChange()
        executeScrollSteps(steps, proxy: proxy)
        scheduleTailUpdate(proxy: proxy)
      }
      .onChange(of: sendTrigger) { _, _ in
        guard anchorsNewUserMessagesToTop else { return }

        withAnimation(bottomInsetAnimation) {
          scrollModel.handleSendTrigger(displayMessages: displayMessages)
        }
      }
      .onChange(of: messages.count) { _, _ in
        let steps = scrollModel.handleMessagesCountChange(displayMessages: displayMessages)
        executeScrollSteps(steps, proxy: proxy)
        scheduleTailUpdate(proxy: proxy)
      }
      .onChange(of: status) { oldStatus, newStatus in
        let steps = scrollModel.handleStatusChange(old: oldStatus, new: newStatus)
        executeScrollSteps(steps, proxy: proxy)

        if newStatus == .streaming {
          startStreamingFollowIfNeeded()
        } else {
          stopStreamingFollow()
        }

        if newStatus != .streaming || (scrollModel.scrollMode != .followBottom || scrollModel.isAtBottom == false) {
          scheduleTailUpdate(proxy: proxy)
        }
      }
      .onChange(of: scrollModel.isAtBottom) { _, _ in
        startStreamingFollowIfNeeded()
      }
      .onChange(of: scrollModel.scrollMode) { _, _ in
        if scrollModel.scrollMode != .followBottom {
          stopStreamingFollow()
        } else {
          startStreamingFollowIfNeeded()
        }

        // When we enter pinned mode, run a tail update once so we can clamp any initial overshoot.
        if case .pinUserMessageToTop = scrollModel.scrollMode {
          scheduleTailUpdate(proxy: proxy)
        }
      }
      .onChange(of: scrollModel.scrollPosition) { _, newValue in
        guard status == .streaming else { return }
        guard let newValue else { return }
        if newValue != conversationBottomSentinelID, newValue != conversationReservedTailSentinelID {
          stopStreamingFollow()
        }
      }
      .onChange(of: scrollToLatestRequest.wrappedValue) { _, _ in
        guard showsScrollButton else { return }
        let steps = scrollModel.handleScrollToLatestButtonTapped()
        executeScrollSteps(steps, proxy: proxy, forceAnimation: scrollAnimation)
        startStreamingFollowIfNeeded()
      }
      #if DEBUG
      .overlay(alignment: .topTrailing) {
        if debugOverlayEnabled {
          debugOverlayButton
        }
      }
      #endif
      // IMPORTANT: Set the preference *outside* the ScrollViewReader. Some container views do not reliably
      // propagate preference values upward when they're set deep in the scroll subtree.
      .preference(
        key: ConversationIsAtLatestForScrollButtonPreferenceKey.self,
        value: scrollModel.isAtLatestForScrollButton
      )
    }
  }

  private var bottomInset: CGFloat {
    scrollModel.bottomInset
  }

  private var shouldMeasureViewport: Bool {
    anchorsNewUserMessagesToTop
      || scrollModel.reservedTailSpace > 0
      || scrollModel.pendingPinToTopAfterSend
      || scrollModel.scrollMode != .followBottom
      || showsScrollButton
      || debugOverlayEnabled
  }

  private var bottomSentinelView: some View {
    VStack(spacing: 0) {
      // Bottom inset creates space above any bottom overlay (e.g. the prompt input).
      Color.clear
        .frame(height: bottomInset)
        .animation(bottomInsetAnimation, value: bottomInset)

      // A 1pt sentinel at the very end so "at bottom" detection isn't delayed by the inset height.
      Color.clear
        .frame(height: 1)
        .background {
          GeometryReader { proxy in
            Color.clear.preference(
              key: BottomSentinelMaxYPreferenceKey.self,
              value: proxy.frame(in: .named(conversationScrollCoordinateSpaceName)).maxY
            )
          }
        }
        .id(conversationBottomSentinelID)
        .onAppear {
          scrollModel.updateBottomSentinelVisibility(isVisible: true)
        }
        .onDisappear {
          scrollModel.updateBottomSentinelVisibility(isVisible: false)
        }
    }
  }

  private var scrollToLatestButtonBottomMargin: CGFloat {
    max(12, theme.spacing.contentPadding.bottom + 16)
  }

  private static func filteredDisplayMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
    messages.filter { $0.role != .system }
  }

  private func measureHeight(id: String) -> some View {
    GeometryReader { proxy in
      Color.clear
        .preference(key: MessageHeightsPreferenceKey.self, value: [id: proxy.size.height])
    }
  }

  private func startStreamingFollowIfNeeded() {
    guard status == .streaming else { return }
    guard scrollModel.scrollMode == .followBottom else { return }
    guard scrollModel.isAtBottom else { return }
    guard streamingFollowTask == nil else { return }

    streamingFollowTask = Task { @MainActor in
      defer { streamingFollowTask = nil }
      while Task.isCancelled == false {
        try? await Task.sleep(nanoseconds: streamingScrollThrottleNanoseconds)
        guard scrollModel.scrollMode == .followBottom else { return }
        withAnimation(streamingScrollAnimation) {
          scrollModel.scrollPosition = conversationBottomSentinelID
        }
      }
    }
  }

  private func stopStreamingFollow() {
    streamingFollowTask?.cancel()
    streamingFollowTask = nil
  }

  private func scheduleTailUpdate(proxy: ScrollViewProxy) {
    guard scrollModel.reservedTailBaseline > 0 else { return }
    guard scrollModel.pinnedUserMessageID != nil else { return }
    guard pendingTailUpdateTask == nil else { return }

    pendingTailUpdateTask = Task { @MainActor in
      defer { pendingTailUpdateTask = nil }
      try? await Task.sleep(nanoseconds: tailUpdateThrottleNanoseconds)
      var steps: [ConversationScrollEngine.Step] = []
      withAnimation(bottomInsetAnimation) {
        steps = scrollModel.computeTailUpdate()
      }
      executeScrollSteps(steps, proxy: proxy, forceAnimation: streamingScrollAnimation)
    }
  }

  private func executeScrollSteps(
    _ steps: [ConversationScrollEngine.Step],
    proxy: ScrollViewProxy,
    forceAnimation: Animation? = nil
  ) {
    guard steps.isEmpty == false else { return }

    Task { @MainActor in
      for step in steps {
        switch step {
        case .yield:
          await Task.yield()

        case .setMode(let mode):
          switch mode {
          case .followBottom:
            scrollModel.scrollMode = .followBottom
          case .pinUserMessageToTop(let messageID):
            scrollModel.scrollMode = .pinUserMessageToTop(messageID: messageID)
            scrollModel.isAtBottom = false
          }

        case .scrollTo(let target, let stepAnchor, let animated):
          let id: String
          let anchor: UnitPoint
          switch target {
          case .bottomSentinel:
            id = conversationBottomSentinelID
          case .reservedTailSentinel:
            id = conversationReservedTailSentinelID
          case .message(let messageID):
            id = messageID
          }

          switch stepAnchor {
          case .top:
            anchor = .top
          case .bottom:
            anchor = .bottom
          }

          let animation = forceAnimation ?? scrollAnimation
          if animated {
            withAnimation(animation) {
              proxy.scrollTo(id, anchor: anchor)
            }
          } else {
            proxy.scrollTo(id, anchor: anchor)
          }

        case .reassertPinnedUserMessageIfNeeded(messageID: _):
          if scrollModel.reservedTailSpace > 0,
             scrollModel.tailSentinelMaxY >= 0,
             ConversationScrollEngine.computeIsAtLatest(maxY: scrollModel.tailSentinelMaxY, viewportHeight: scrollModel.viewportHeight) == false {
            withAnimation(scrollAnimation) {
              proxy.scrollTo(conversationReservedTailSentinelID, anchor: .bottom)
            }
          }
        }
      }
    }
  }

  #if DEBUG
  private var debugOverlayButton: some View {
    Button {
      copyConversationDebugStateToPasteboard()
    } label: {
      HStack(spacing: 8) {
        Text("DBG")
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
        Text(didCopyDebugState ? "Copied" : "Copy state")
          .font(.system(size: 12, weight: .regular))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .glassEffect(.clear.interactive(), in: .capsule)
      .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .padding(.trailing, 10)
    .padding(.top, 10)
  }

  private func copyConversationDebugStateToPasteboard() {
    let text = debugStateString()

    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #elseif canImport(AppKit)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    #endif

    didCopyDebugState = true
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 900_000_000)
      didCopyDebugState = false
    }
  }

  private func debugStateString() -> String {
    let pinned = scrollModel.pinnedUserMessageID ?? "nil"
    let displayMessages = Self.filteredDisplayMessages(messages)

    return [
      "AIKitElements.Conversation debug",
      "status=\(status)",
      "scrollMode=\(scrollModel.scrollMode)",
      "isAtBottom=\(scrollModel.isAtBottom)",
      "scrollPosition=\(scrollModel.scrollPosition ?? "nil")",
      "viewportHeight=\(String(format: "%.1f", scrollModel.viewportHeight))",
      "maxViewportHeightSinceAppear=\(String(format: "%.1f", scrollModel.maxViewportHeightSinceAppear))",
      "keyboardInsetApprox=\(String(format: "%.1f", scrollModel.keyboardInsetApprox))",
      "bottomInset=\(String(format: "%.1f", bottomInset))",
      "reservedTailSpace=\(String(format: "%.1f", scrollModel.reservedTailSpace))",
      "reservedTailBaseline=\(String(format: "%.1f", scrollModel.reservedTailBaseline))",
      "bottomSentinelIsVisible=\(scrollModel.debugBottomSentinelIsVisible)",
      "tailSentinelIsVisible=\(scrollModel.debugTailSentinelIsVisible)",
      "bottomSentinelMaxY=\(String(format: "%.1f", scrollModel.bottomSentinelMaxY))",
      "tailSentinelMaxY=\(String(format: "%.1f", scrollModel.tailSentinelMaxY))",
      "bottomSentinelDelta=\(String(format: "%.1f", scrollModel.bottomSentinelMaxY - scrollModel.viewportHeight))",
      "tailSentinelDelta=\(String(format: "%.1f", scrollModel.tailSentinelMaxY - scrollModel.viewportHeight))",
      "isAtLatestForScrollButton=\(scrollModel.isAtLatestForScrollButton)",
      "pendingPinToTopAfterSend=\(scrollModel.pendingPinToTopAfterSend)",
      "pendingSendAnchoringMessageID=\(scrollModel.debugPendingSendAnchoringMessageID ?? "nil")",
      "pinnedUserMessageID=\(pinned)",
      "displayMessages.count=\(displayMessages.count)",
      "visibleMessages.count=\(scrollModel.visibleMessages(displayMessages: displayMessages).count)",
      "knownDisplayMessageIDs.count=\(scrollModel.debugKnownDisplayMessageIDsCount)",
      "preSendDisplayMessageIDs.count=\(scrollModel.debugPreSendDisplayMessageIDsCount)",
      "postSendDisplayMessageIDs.count=\(scrollModel.debugPostSendDisplayMessageIDsCount)",
      "messageHeights.count=\(scrollModel.debugMessageHeightsCount)",
    ].joined(separator: "\n")
  }
  #endif

  private struct DefaultMessageView: View {
    let message: ChatMessage

    @Environment(\.conversationOnEditUserMessage) private var onEditUserMessage

    var body: some View {
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
          .contentShape(Rectangle())
          .contextMenu {
            if let onEditUserMessage {
              Button("Edit") {
                onEditUserMessage(message)
              }
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

private enum MessageHeightsPreferenceKey: PreferenceKey {
  static var defaultValue: [String: CGFloat] { [:] }

  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
