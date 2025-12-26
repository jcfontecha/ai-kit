import Foundation
import AIKitProviders

/// Swift analogue to the AI SDK UI `ChatTransport` interface used by `useChat`.
///
/// This protocol is intentionally narrow: it represents a client that can
/// talk to a server that runs the AI SDK and streams the **UI message stream protocol** (SSE v1).
///
/// Source of truth:
/// - `ai-sdk/packages/ai/src/ui/chat-transport.ts`
/// - `ai-sdk/packages/ai/src/ui/http-chat-transport.ts`
public protocol ChatTransport: Sendable {
  func sendMessages(
    _ options: ChatTransportSendMessagesOptions
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>

  func reconnectToStream(
    _ options: ChatTransportReconnectToStreamOptions
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>?
}

public struct ChatTransportSendMessagesOptions: Sendable {
  /// AI SDK `chatId`.
  public var chatID: String

  /// AIKit UI transcript.
  public var messages: [ChatMessage]

  /// AI SDK `trigger` (`submit-message` / `regenerate-message`).
  public var trigger: ChatRequestTrigger

  /// AI SDK `messageId` (used for regenerate flows).
  public var messageID: String?

  /// Mirrors AI SDK `ChatRequestOptions` (headers/body/metadata).
  public var options: ChatRequestOptions?

  /// Mirrors AI SDK `abortSignal` use cases (optional).
  public var cancellationToken: CancellationToken?

  public init(
    chatID: String,
    messages: [ChatMessage],
    trigger: ChatRequestTrigger,
    messageID: String?,
    options: ChatRequestOptions?,
    cancellationToken: CancellationToken?
  ) {
    self.chatID = chatID
    self.messages = messages
    self.trigger = trigger
    self.messageID = messageID
    self.options = options
    self.cancellationToken = cancellationToken
  }
}

public struct ChatTransportReconnectToStreamOptions: Sendable {
  public var chatID: String
  public var options: ChatRequestOptions?

  public init(chatID: String, options: ChatRequestOptions?) {
    self.chatID = chatID
    self.options = options
  }
}

public extension ChatTransport {
  func makeRequestStream() -> ChatSessionInit.RequestStream {
    { chatID, messages, trigger, messageID, options, cancellationToken in
      try await sendMessages(.init(
        chatID: chatID,
        messages: messages,
        trigger: trigger,
        messageID: messageID,
        options: options,
        cancellationToken: cancellationToken
      ))
    }
  }

  func makeReconnectToStream() -> ChatSessionInit.ReconnectToStream {
    { chatID, options in
      try await reconnectToStream(.init(chatID: chatID, options: options))
    }
  }
}
