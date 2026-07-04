import SwiftUI
import AIKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let conversationEndMarkerID = "aikit.conversation.end-marker"
private let conversationContentSpaceName = "aikit.conversation.content"

public struct Conversation<MessageView: View>: View {
  public var messages: [ChatMessage]
  public var status: ChatStatus
  @ViewBuilder public var messageView: (ChatMessage) -> MessageView

  @Environment(\.chatTheme) private var theme
  @Environment(\.conversationBottomOverlayHeight) private var bottomOverlayHeight
  @Environment(\.conversationShowsScrollButton) private var showsScrollButton
  @Environment(\.conversationAnchorsNewUserMessagesToTop) private var anchorsNewUserMessagesToTop
  @Environment(\.conversationDebugOverlayEnabled) private var debugOverlayEnabled
  @Environment(\.conversationTopOverlayHeight) private var topOverlayHeight
  @Environment(\.conversationScrollToLatestRequest) private var scrollToLatestRequest

  @State private var position = ScrollPosition(edge: .bottom)
  @State private var scroller = ConversationScroller()
  #if DEBUG
  @State private var didCopyDebugState: Bool = false
  #endif

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
      AnyView(DefaultMessageView(message: message))
    }
  }

  public var body: some View {
    let displayMessages = Self.filteredDisplayMessages(messages)
    let visibleMessages = Array(displayMessages.suffix(min(scroller.visibleCount, displayMessages.count)))
    let rows = visibleMessages.map { message in
      ConversationScrollRow(id: message.id, isAnchor: anchorsNewUserMessagesToTop && message.role == .user)
    }

    ScrollViewReader { proxy in
      ScrollView {
        // Everything outside the LazyVStack is non-lazy and always laid out:
        // the end marker is both the layout-true content-bottom measurement
        // and the toEnd scroll target, so lazy estimate error cancels out of
        // at-end detection. The tail spacer sits after it and never counts as
        // content.
        VStack(alignment: .leading, spacing: 0) {
          LazyVStack(alignment: .leading, spacing: theme.spacing.messageRow) {
            ForEach(visibleMessages) { message in
              messageView(message)
                .id(message.id)
                .onGeometryChange(for: CGFloat.self) { proxy in
                  proxy.frame(in: .scrollView).minY
                } action: { _, minY in
                  guard message.id == scroller.anchoredMessageID else { return }
                  apply(scroller.anchorRowFrame(viewportTop: minY), proxy: proxy)
                }
            }
          }
          .padding(theme.spacing.contentPadding)

          Color.clear
            .frame(height: 1)
            .id(conversationEndMarkerID)
            .onGeometryChange(for: CGFloat.self) { proxy in
              // Content coordinates: scroll-invariant, changes only on real
              // layout changes — never races the offset stream.
              proxy.frame(in: .named(conversationContentSpaceName)).maxY
            } action: { _, contentMaxY in
              apply(scroller.endMarker(contentMaxY: contentMaxY), proxy: proxy)
            }

          if scroller.spacerHeight > 0 {
            // Tail spacer: gives short turns enough scroll range to reach the
            // reading line, then shrinks 1:1 as the reply streams in below.
            Color.clear.frame(height: scroller.spacerHeight)
          }
        }
        .coordinateSpace(name: conversationContentSpaceName)
      }
      .scrollPosition($position)
      // Native follow: while at the live edge, content growth and viewport
      // resizes (keyboard, composer) keep the bottom pinned in the same layout
      // pass. Released modes anchor to the top so growth below never moves the
      // reader. Repeated scrollTo(edge:) pin commands cannot do this —
      // ScrollPosition is state-diffed and drops them. The opening position
      // comes from the ScrollPosition(edge: .bottom) initial value; the churn
      // and marker pins correct any drift the estimates introduce after that.
      .defaultScrollAnchor(scroller.isFollowing ? .bottom : .top, for: .sizeChanges)
      .contentMargins(.top, topOverlayHeight, for: .scrollContent)
      .contentMargins(.bottom, ConversationScrollerConstants.extraBottomPadding + bottomOverlayHeight, for: .scrollContent)
      .onScrollGeometryChange(for: ConversationScrollGeometry.self) { geometry in
        ConversationScrollGeometry(
          offsetY: geometry.contentOffset.y,
          contentHeight: geometry.contentSize.height,
          containerHeight: geometry.containerSize.height,
          topInset: geometry.contentInsets.top,
          bottomInset: geometry.contentInsets.bottom
        )
      } action: { _, newGeometry in
        apply(scroller.geometryChange(newGeometry, totalDisplayCount: displayMessages.count), proxy: proxy)
      }
      .onScrollPhaseChange { _, newPhase, _ in
        apply(scroller.scrollPhase(Self.mapScrollPhase(newPhase)), proxy: proxy)
      }
      .scrollEdgeEffectStyle(.soft, for: .bottom)
      #if os(iOS)
      .scrollDismissesKeyboard(.interactively)
      #endif
      .onAppear {
        apply(scroller.appear(rows: rows), proxy: proxy)
      }
      .onChange(of: rows) { _, newRows in
        apply(scroller.contentChange(
          rows: newRows,
          rowGap: theme.spacing.messageRow,
          bottomContentPadding: theme.spacing.contentPadding.bottom
        ), proxy: proxy)
      }
      .onChange(of: scrollToLatestRequest.wrappedValue) { _, _ in
        guard showsScrollButton else { return }
        apply(scroller.scrollToEndRequested(), proxy: proxy)
      }
      #if DEBUG
      .overlay(alignment: .topTrailing) {
        if debugOverlayEnabled {
          debugOverlayButton
        }
      }
      #endif
    }
    // Set the preference outside the ScrollViewReader: preference values set
    // deep inside the scroll subtree don't propagate reliably.
    .preference(
      key: ConversationIsAtLatestForScrollButtonPreferenceKey.self,
      value: scroller.isAtEnd
    )
  }

  private func apply(_ command: ConversationScrollCommand?, proxy: ScrollViewProxy) {
    guard let command else { return }
    // Commands are emitted from geometry/layout callbacks, where a proxy
    // scroll is a no-op; hop off the current update before executing.
    Task { @MainActor in
      switch command {
      case .toEnd(let animated):
        if animated {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(conversationEndMarkerID, anchor: .bottom)
          }
        } else {
          proxy.scrollTo(conversationEndMarkerID, anchor: .bottom)
        }
      case .toOffset(let y):
        // The core computes offsets in ScrollGeometry.contentOffset space;
        // ScrollPosition.scrollTo(y:) lands at contentOffset = y − topInset
        // (verified in the sheet demo: commanded 10948.3, landed 10878.3 with
        // topInset 70). Translate so the command means what the core computed.
        position.scrollTo(y: y + scroller.core.geometry.topInset)
      case .toRowTop(let id):
        proxy.scrollTo(id, anchor: .top)
      }
    }
  }

  private static func mapScrollPhase(_ phase: ScrollPhase) -> ConversationScrollPhase {
    switch phase {
    case .idle: return .idle
    case .tracking: return .tracking
    case .interacting: return .interacting
    case .animating: return .animating
    case .decelerating: return .decelerating
    @unknown default: return .idle
    }
  }

  private static func filteredDisplayMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
    messages.filter { $0.role != .system }
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
    let core = scroller.core
    let geometry = core.geometry
    let displayMessages = Self.filteredDisplayMessages(messages)

    return [
      "AIKitElements.Conversation debug",
      "status=\(status)",
      "mode=\(core.mode)",
      "isAtEnd=\(core.isAtEnd)",
      "distanceFromEnd=\(String(format: "%.1f", core.distanceFromEnd))",
      "endMarkerContentMaxY=\(String(format: "%.1f", core.endMarkerContentMaxY))",
      "spacerHeight=\(String(format: "%.1f", core.spacerHeight))",
      "anchoredMessageID=\(core.anchoredRowID ?? "nil")",
      "geometry.offsetY=\(String(format: "%.1f", geometry.offsetY))",
      "geometry.contentHeight=\(String(format: "%.1f", geometry.contentHeight))",
      "geometry.containerHeight=\(String(format: "%.1f", geometry.containerHeight))",
      "geometry.topInset=\(String(format: "%.1f", geometry.topInset))",
      "geometry.bottomInset=\(String(format: "%.1f", geometry.bottomInset))",
      "visibleCount=\(core.visibleCount)",
      "displayMessages.count=\(displayMessages.count)",
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
