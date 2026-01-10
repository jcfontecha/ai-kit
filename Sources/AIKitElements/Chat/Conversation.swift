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
  @Environment(\.conversationTopOverlayHeight) private var topOverlayHeight
  @Environment(\.conversationScrollToLatestRequest) private var scrollToLatestRequest

  @StateObject private var scrollModel = ConversationScrollViewModel()
  @State private var streamingFollowTask: Task<Void, Never>?
  @State private var pendingTailUpdateTask: Task<Void, Never>?
  @State private var scrollDispatcher = ConversationScrollDispatcher()
  @State private var interactionUnlockTask: Task<Void, Never>?
  @State private var isStickyFollowingTail: Bool = false
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
              messageView(message)
                .id(message.id)
                .background {
                  if scrollModel.shouldMeasureMessageHeights {
                    measureHeight(id: message.id)
                  }
                }
            }
          }

          bottomSentinelView

          if scrollModel.reservedTailSpace > 0 {
            // Tail spacer creates scroll range so the newest user message can be pinned to the top.
            Color.clear
              .frame(height: scrollModel.reservedTailSpace)

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

            // Keep a tiny amount of scrollable content below the reserved-tail sentinel so the ScrollView isn't
            // exactly at its max offset (which would cause SwiftUI to auto-pin to bottom during streaming updates).
            Color.clear
              .frame(height: 4)
          }
        }
        .padding(theme.spacing.contentPadding)
      }
      .coordinateSpace(name: conversationScrollCoordinateSpaceName)
      .scrollDisabled(scrollModel.isScrollInteractionDisabled)
      .background {
        #if canImport(UIKit)
        ConversationScrollViewPanPassthrough()
          .frame(width: 0, height: 0)
        #endif
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 2).onChanged { _ in
          scrollModel.handleUserScrollIntervention()
          scrollDispatcher.cancel()
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
      .modifier(ScrollEdgeEffectCompat())
      // Default anchoring to `.bottom` causes visible content to shift during streaming content growth.
      // Keep a stable top-anchored viewport; we explicitly scroll to follow the tail when desired.
      .defaultScrollAnchor(.top)
      #if os(iOS)
      .modifier(ScrollDismissesKeyboardCompat())
      #endif
      .onAppear {
        scrollModel.updateBottomOverlayHeight(bottomOverlayHeight)
        scrollModel.updateLiftedUserMessageTargetMinYIfNeeded(topOverlayHeight + theme.spacing.contentPadding.top)
        let steps = scrollModel.handleOnAppear(displayMessages: displayMessages)
        executeScrollSteps(steps, proxy: proxy)
        startStreamingFollowIfNeeded(proxy: proxy)
      }
      .onDisappear {
        stopStreamingFollow()
        pendingTailUpdateTask?.cancel()
        pendingTailUpdateTask = nil
        interactionUnlockTask?.cancel()
        interactionUnlockTask = nil
        scrollDispatcher.cancel()
      }
      .onChange(of: bottomOverlayHeight) { _, newValue in
        scrollModel.updateBottomOverlayHeight(newValue)
        let steps = scrollModel.handleBottomInsetChange()
        executeScrollSteps(steps, proxy: proxy)
        scheduleTailUpdate(proxy: proxy)
      }
      .onChange(of: topOverlayHeight) { _, newValue in
        scrollModel.updateLiftedUserMessageTargetMinYIfNeeded(newValue + theme.spacing.contentPadding.top)
        scheduleTailUpdate(proxy: proxy)
      }
      .onChange(of: sendTrigger) { _, _ in
        guard anchorsNewUserMessagesToTop else { return }
        scrollModel.handleSendTrigger(displayMessages: displayMessages)
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
          startStreamingFollowIfNeeded(proxy: proxy)
        } else {
          stopStreamingFollow()
        }

        if newStatus != .streaming || scrollModel.isAtBottom == false {
          scheduleTailUpdate(proxy: proxy)
        }
      }
      .onChange(of: scrollModel.isAtBottom) { _, _ in
        if scrollModel.isAtBottom {
          startStreamingFollowIfNeeded(proxy: proxy)
        }
      }
      .onChange(of: scrollToLatestRequest.wrappedValue) { _, _ in
        guard showsScrollButton else { return }
        let steps = scrollModel.handleScrollToLatestButtonTapped()
        executeScrollSteps(steps, proxy: proxy, forceAnimation: scrollAnimation)
        startStreamingFollowIfNeeded(proxy: proxy, assumeWantsFollow: true)
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
      || scrollModel.pendingLiftAfterSend
      || scrollModel.isScrollInteractionDisabled
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

  private func startStreamingFollowIfNeeded(proxy: ScrollViewProxy, assumeWantsFollow: Bool = false) {
    guard status == .streaming else { return }
    guard scrollModel.isScrollInteractionDisabled == false else { return }
    // While reserve-mode is active, we want the lifted user message to remain visually stable while the assistant
    // fills the reserved space. Following the tail would fight that.
    guard scrollModel.reservedTailSpace <= 0 else { return }

    if assumeWantsFollow {
      isStickyFollowingTail = true
    } else {
      guard scrollModel.isAtBottom else { return }
      isStickyFollowingTail = true
    }

    guard streamingFollowTask == nil else { return }

    streamingFollowTask = Task { @MainActor in
      defer { streamingFollowTask = nil }
      while Task.isCancelled == false {
        try? await Task.sleep(nanoseconds: streamingScrollThrottleNanoseconds)
        guard isStickyFollowingTail else { return }
        guard status == .streaming else { return }
        guard scrollModel.isScrollInteractionDisabled == false else { return }
        guard scrollModel.reservedTailSpace <= 0 else { return }
        if scrollDispatcher.isBusy { continue }

        if scrollModel.viewportHeight > 0, scrollModel.bottomSentinelMaxY >= 0 {
          if ConversationScrollEngine.computeIsAtLatest(maxY: scrollModel.bottomSentinelMaxY, viewportHeight: scrollModel.viewportHeight) {
            continue
          }
        }

        let id = scrollModel.reservedTailSpace > 0 ? conversationReservedTailSentinelID : conversationBottomSentinelID
        withAnimation(streamingScrollAnimation) {
          proxy.scrollTo(id, anchor: .bottom)
        }
      }
    }
  }

  private func stopStreamingFollow() {
    isStickyFollowingTail = false
    streamingFollowTask?.cancel()
    streamingFollowTask = nil
  }

  private func scheduleTailUpdate(proxy: ScrollViewProxy) {
    guard scrollModel.liftedUserMessageID != nil else { return }
    guard pendingTailUpdateTask == nil else { return }

    pendingTailUpdateTask = Task { @MainActor in
      defer { pendingTailUpdateTask = nil }
      try? await Task.sleep(nanoseconds: tailUpdateThrottleNanoseconds)
      let steps = scrollModel.computeTailUpdate()
      executeScrollSteps(steps, proxy: proxy, replaceQueue: false, forceAnimation: streamingScrollAnimation)

      // If we just exited reserve-mode due to overflow, we may temporarily not be "at bottom" by measurement yet.
      // Start sticky follow anyway so we keep tracking the assistant tail as it continues streaming.
      let didScrollToBottom = steps.contains { step in
        if case .scrollTo(target: .bottomSentinel, anchor: .bottom, animated: _) = step { return true }
        return false
      }

      startStreamingFollowIfNeeded(proxy: proxy, assumeWantsFollow: didScrollToBottom)
    }
  }

  private func executeScrollSteps(
    _ steps: [ConversationScrollEngine.Step],
    proxy: ScrollViewProxy,
    replaceQueue: Bool = true,
    forceAnimation: Animation? = nil
  ) {
    guard steps.isEmpty == false else { return }

    let resolvedAnimation = forceAnimation ?? scrollAnimation
    scrollDispatcher.submit(
      steps,
      proxy: proxy,
      forceAnimation: resolvedAnimation,
      replaceQueue: replaceQueue,
      reassertLatestIfNeeded: { [scrollModel, resolvedAnimation] proxy, animation in
        let metrics = ConversationScrollEngine.LatestMetrics(
          viewportHeight: scrollModel.viewportHeight,
          reservedTailSpace: scrollModel.reservedTailSpace,
          bottomSentinelMaxY: scrollModel.bottomSentinelMaxY,
          tailSentinelMaxY: scrollModel.tailSentinelMaxY
        )
        if ConversationScrollEngine.computeIsAtLatest(metrics: metrics) == false {
          let id = scrollModel.reservedTailSpace > 0 ? conversationReservedTailSentinelID : conversationBottomSentinelID
          withAnimation(animation ?? resolvedAnimation) {
            proxy.scrollTo(id, anchor: .bottom)
          }
        }
      }
    )

    if scrollModel.isScrollInteractionDisabled {
      interactionUnlockTask?.cancel()
      interactionUnlockTask = Task { @MainActor [scrollModel] in
        // Match Conversation scroll animation tuning (plus a small buffer).
        try? await Task.sleep(nanoseconds: 320_000_000)
        scrollModel.releaseScrollInteractionIfNeeded()
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
    let lifted = scrollModel.liftedUserMessageID ?? "nil"
    let displayMessages = Self.filteredDisplayMessages(messages)

    return [
      "AIKitElements.Conversation debug",
      "status=\(status)",
      "isAtBottom=\(scrollModel.isAtBottom)",
      "isScrollInteractionDisabled=\(scrollModel.isScrollInteractionDisabled)",
      "viewportHeight=\(String(format: "%.1f", scrollModel.viewportHeight))",
      "maxViewportHeightSinceAppear=\(String(format: "%.1f", scrollModel.maxViewportHeightSinceAppear))",
      "keyboardInsetApprox=\(String(format: "%.1f", scrollModel.keyboardInsetApprox))",
      "bottomInset=\(String(format: "%.1f", bottomInset))",
      "reservedTailSpace=\(String(format: "%.1f", scrollModel.reservedTailSpace))",
      "bottomSentinelIsVisible=\(scrollModel.debugBottomSentinelIsVisible)",
      "tailSentinelIsVisible=\(scrollModel.debugTailSentinelIsVisible)",
      "bottomSentinelMaxY=\(String(format: "%.1f", scrollModel.bottomSentinelMaxY))",
      "tailSentinelMaxY=\(String(format: "%.1f", scrollModel.tailSentinelMaxY))",
      "bottomSentinelDelta=\(String(format: "%.1f", scrollModel.bottomSentinelMaxY - scrollModel.viewportHeight))",
      "tailSentinelDelta=\(String(format: "%.1f", scrollModel.tailSentinelMaxY - scrollModel.viewportHeight))",
      "isAtLatestForScrollButton=\(scrollModel.isAtLatestForScrollButton)",
      "liftedUserMessageTargetMinY=\(String(format: "%.1f", scrollModel.debugLiftedUserMessageTargetMinY))",
      "pendingLiftAfterSend=\(scrollModel.pendingLiftAfterSend)",
      "pendingLiftAlignmentMessageID=\(scrollModel.debugPendingLiftAlignmentMessageID ?? "nil")",
      "liftedUserMessageID=\(lifted)",
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
