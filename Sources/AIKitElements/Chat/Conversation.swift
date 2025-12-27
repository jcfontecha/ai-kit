import SwiftUI
import AIKit

public struct Conversation<MessageView: View>: View {
  public var messages: [ChatMessage]
  public var bottomOverlayHeight: CGFloat
  @ViewBuilder public var messageView: (ChatMessage) -> MessageView

  public init(
    messages: [ChatMessage],
    bottomOverlayHeight: CGFloat,
    @ViewBuilder messageView: @escaping (ChatMessage) -> MessageView
  ) {
    self.messages = messages
    self.bottomOverlayHeight = bottomOverlayHeight
    self.messageView = messageView
  }

  public var body: some View {
    ScrollViewReader { proxy in
      let scrollView = ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(messages) { message in
            messageView(message)
              .id(message.id)
          }

          Color.clear
            .frame(height: bottomInsetHeight)
            .id("bottom")
        }
        .padding(12)
      }

      Group {
        if #available(iOS 26.0, macOS 26.0, *) {
          scrollView.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
          scrollView
        }
      }
      .onChange(of: messages.last?.id) { _ in
        withAnimation(.easeInOut(duration: 0.2)) {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      }
    }
  }

  private var bottomInsetHeight: CGFloat {
    max(1, bottomOverlayHeight - 28)
  }
}
