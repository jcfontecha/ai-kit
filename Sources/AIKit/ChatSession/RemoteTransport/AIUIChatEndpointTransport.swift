import Foundation
import AIKitProviders

/// A small Swift analogue to the AI SDK's `HttpChatTransport` for non-JS clients.
///
/// Source of truth for request shape defaults:
/// `ai-sdk/packages/ai/src/ui/http-chat-transport.ts`
struct AIUIChatEndpointTransport: Sendable {
  public enum TransportBodyError: Error, Sendable, Equatable {
    case expectedJSONObject
  }

  public struct PrepareSendMessagesRequestOptions: Sendable {
    public var url: URL
    public var chatID: String
    public var messages: [AIUIMessage]
    public var trigger: ChatRequestTrigger
    public var messageID: String?
    public var requestMetadata: JSONValue?
    public var body: [String: JSONValue]?
    public var headers: [String: String]

    public init(
      url: URL,
      chatID: String,
      messages: [AIUIMessage],
      trigger: ChatRequestTrigger,
      messageID: String?,
      requestMetadata: JSONValue?,
      body: [String: JSONValue]?,
      headers: [String: String]
    ) {
      self.url = url
      self.chatID = chatID
      self.messages = messages
      self.trigger = trigger
      self.messageID = messageID
      self.requestMetadata = requestMetadata
      self.body = body
      self.headers = headers
    }
  }

  public struct PreparedSendMessagesRequest: Sendable {
    public var url: URL?
    public var body: [String: JSONValue]?
    public var headers: [String: String]?

    public init(
      url: URL? = nil,
      body: [String: JSONValue]? = nil,
      headers: [String: String]? = nil
    ) {
      self.url = url
      self.body = body
      self.headers = headers
    }
  }

  public typealias PrepareSendMessagesRequest = @Sendable (PrepareSendMessagesRequestOptions) async throws -> PreparedSendMessagesRequest?

  public struct PrepareReconnectToStreamRequestOptions: Sendable {
    public var url: URL
    public var chatID: String
    public var requestMetadata: JSONValue?
    public var body: [String: JSONValue]?
    public var headers: [String: String]

    public init(
      url: URL,
      chatID: String,
      requestMetadata: JSONValue?,
      body: [String: JSONValue]?,
      headers: [String: String]
    ) {
      self.url = url
      self.chatID = chatID
      self.requestMetadata = requestMetadata
      self.body = body
      self.headers = headers
    }
  }

  public struct PreparedReconnectToStreamRequest: Sendable {
    public var url: URL?
    public var headers: [String: String]?

    public init(
      url: URL? = nil,
      headers: [String: String]? = nil
    ) {
      self.url = url
      self.headers = headers
    }
  }

  public typealias PrepareReconnectToStreamRequest = @Sendable (PrepareReconnectToStreamRequestOptions) async throws -> PreparedReconnectToStreamRequest?

  public var url: URL
  public var httpTransport: any HTTPTransport
  public var headers: (@Sendable () async throws -> [String: String])?
  public var body: (@Sendable () async throws -> JSONValue?)?
  public var userAgentSuffix: String
  public var encoder: AIUIMessageEncoder
  public var streamClient: AIUIMessageStreamClient
  public var prepareSendMessagesRequest: PrepareSendMessagesRequest?
  public var prepareReconnectToStreamRequest: PrepareReconnectToStreamRequest?

  public init(
    url: URL,
    httpTransport: any HTTPTransport,
    headers: (@Sendable () async throws -> [String: String])? = nil,
    body: (@Sendable () async throws -> JSONValue?)? = nil,
    userAgentSuffix: String = "aikit/swift",
    encoder: AIUIMessageEncoder = .init(),
    streamClient: AIUIMessageStreamClient? = nil,
    prepareSendMessagesRequest: PrepareSendMessagesRequest? = nil,
    prepareReconnectToStreamRequest: PrepareReconnectToStreamRequest? = nil
  ) {
    self.url = url
    self.httpTransport = httpTransport
    self.headers = headers
    self.body = body
    self.userAgentSuffix = userAgentSuffix
    self.encoder = encoder
    self.streamClient = streamClient ?? .init(transport: httpTransport)
    self.prepareSendMessagesRequest = prepareSendMessagesRequest
    self.prepareReconnectToStreamRequest = prepareReconnectToStreamRequest
  }

  public init(
    url: URL,
    httpTransport: any HTTPTransport,
    headers: [String: String],
    body: JSONValue? = nil,
    userAgentSuffix: String = "aikit/swift",
    encoder: AIUIMessageEncoder = .init(),
    streamClient: AIUIMessageStreamClient? = nil,
    prepareSendMessagesRequest: PrepareSendMessagesRequest? = nil,
    prepareReconnectToStreamRequest: PrepareReconnectToStreamRequest? = nil
  ) {
    self.init(
      url: url,
      httpTransport: httpTransport,
      headers: { headers },
      body: { body },
      userAgentSuffix: userAgentSuffix,
      encoder: encoder,
      streamClient: streamClient,
      prepareSendMessagesRequest: prepareSendMessagesRequest,
      prepareReconnectToStreamRequest: prepareReconnectToStreamRequest
    )
  }

  public init(
    url: URL,
    httpTransport: any HTTPTransport,
    body: JSONValue?,
    userAgentSuffix: String = "aikit/swift",
    encoder: AIUIMessageEncoder = .init(),
    streamClient: AIUIMessageStreamClient? = nil,
    prepareSendMessagesRequest: PrepareSendMessagesRequest? = nil,
    prepareReconnectToStreamRequest: PrepareReconnectToStreamRequest? = nil
  ) {
    self.init(
      url: url,
      httpTransport: httpTransport,
      headers: nil,
      body: { body },
      userAgentSuffix: userAgentSuffix,
      encoder: encoder,
      streamClient: streamClient,
      prepareSendMessagesRequest: prepareSendMessagesRequest,
      prepareReconnectToStreamRequest: prepareReconnectToStreamRequest
    )
  }

  private func applyUserAgentSuffix(to request: inout URLRequest) {
    guard !userAgentSuffix.isEmpty else { return }
    let existing = request.value(forHTTPHeaderField: "User-Agent")
    let updated: String
    if let existing, !existing.isEmpty {
      if existing.contains(userAgentSuffix) {
        updated = existing
      } else {
        updated = "\(existing) \(userAgentSuffix)"
      }
    } else {
      updated = userAgentSuffix
    }
    request.setValue(updated, forHTTPHeaderField: "User-Agent")
  }

  /// Creates a stream of `TextStreamPart` by POSTing AI SDK UI messages to a server endpoint that returns
  /// an AI SDK UI message stream (SSE v1).
  public func requestStream(
    chatID: String,
    messages: [ChatMessage],
    trigger: ChatRequestTrigger,
    messageID: String?,
    options: ChatRequestOptions?
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let transportHeaders = try await headers?() ?? [:]
    let baseHeaders = transportHeaders.merging(options?.headers ?? [:], uniquingKeysWith: { _, new in new })

    let uiMessages = try encoder.encode(messages)
    let messagesData = try JSONEncoder().encode(uiMessages)
    let messagesObject = try JSONSerialization.jsonObject(with: messagesData, options: [.fragmentsAllowed])
    let messagesJSON = JSONValue.from(messagesObject) ?? .null

    var resolvedBody: [String: JSONValue] = [:]
    if let transportBody = try await body?() {
      guard case let .object(obj) = transportBody else { throw TransportBodyError.expectedJSONObject }
      resolvedBody = obj
    }

    var extraBody: [String: JSONValue] = [:]
    extraBody.merge(resolvedBody, uniquingKeysWith: { _, new in new })
    if case let .object(extra)? = options?.body {
      extraBody.merge(extra, uniquingKeysWith: { _, new in new })
    }

    let prepared = try await prepareSendMessagesRequest?(PrepareSendMessagesRequestOptions(
      url: url,
      chatID: chatID,
      messages: uiMessages,
      trigger: trigger,
      messageID: messageID,
      requestMetadata: options?.metadata,
      body: extraBody.isEmpty ? nil : extraBody,
      headers: baseHeaders
    ))

    let effectiveURL = prepared?.url ?? url
    let effectiveHeaders = prepared?.headers ?? baseHeaders

    for (k, v) in effectiveHeaders {
      request.setValue(v, forHTTPHeaderField: k)
    }

    applyUserAgentSuffix(to: &request)
    request.url = effectiveURL

    let body: [String: JSONValue]
    if let preparedBody = prepared?.body {
      body = preparedBody
    } else {
      // Match AI SDK HttpChatTransport defaults: id/messages are always present and take precedence.
      var defaultBody = extraBody
      defaultBody["id"] = .string(chatID)
      defaultBody["messages"] = messagesJSON
      defaultBody["trigger"] = .string(trigger.rawValue)
      if let messageID {
        defaultBody["messageId"] = .string(messageID)
      }
      body = defaultBody
    }

    request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

    return try await streamClient.streamParts(for: request)
  }

  /// Reconnects to an existing UI message stream for a chatID.
  ///
  /// Mirrors AI SDK `HttpChatTransport.reconnectToStream` defaults:
  /// - GET `\(api)/:id/stream`
  /// - 204 => return `nil` (no active stream)
  public func reconnectToStream(
    chatID: String,
    options: ChatRequestOptions?
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>? {
    let transportHeaders = try await headers?() ?? [:]
    let baseHeaders = transportHeaders.merging(options?.headers ?? [:], uniquingKeysWith: { _, new in new })

    var extraBody: [String: JSONValue] = [:]
    if let transportBody = try await body?() {
      guard case let .object(obj) = transportBody else { throw TransportBodyError.expectedJSONObject }
      extraBody.merge(obj, uniquingKeysWith: { _, new in new })
    }
    if case let .object(extra)? = options?.body {
      extraBody.merge(extra, uniquingKeysWith: { _, new in new })
    }

    let prepared = try await prepareReconnectToStreamRequest?(PrepareReconnectToStreamRequestOptions(
      url: url,
      chatID: chatID,
      requestMetadata: options?.metadata,
      body: extraBody.isEmpty ? nil : extraBody,
      headers: baseHeaders
    ))

    let defaultResumeURL = url.appendingPathComponent(chatID).appendingPathComponent("stream")
    let effectiveURL = prepared?.url ?? defaultResumeURL
    let effectiveHeaders = prepared?.headers ?? baseHeaders

    var request = URLRequest(url: effectiveURL)
    request.httpMethod = "GET"

    for (k, v) in effectiveHeaders {
      request.setValue(v, forHTTPHeaderField: k)
    }

    applyUserAgentSuffix(to: &request)
    let (bytes, response) = try await httpTransport.bytes(for: request)

    // no active stream found, so we do not resume
    if response.statusCode == 204 {
      return nil
    }

    // Delegate header validation + SSE decoding to the stream client.
    try AIUIMessageStreamClient.validateUIMessageStreamHeader(response)
    return streamClient.decoder.decode(bytes)
  }

  public func requestStream(
    chatID: String,
    messages: [ChatMessage],
    options: ChatRequestOptions?
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    try await requestStream(
      chatID: chatID,
      messages: messages,
      trigger: .submitMessage,
      messageID: messages.last?.id,
      options: options
    )
  }

  func makeRequestStream() -> ChatSessionInit.RequestStream {
    { chatID, messages, trigger, messageID, options, _ in
      try await requestStream(
        chatID: chatID,
        messages: messages,
        trigger: trigger,
        messageID: messageID,
        options: options
      )
    }
  }

  func makeReconnectToStream() -> ChatSessionInit.ReconnectToStream {
    { chatID, options in
      try await reconnectToStream(chatID: chatID, options: options)
    }
  }
}

extension AIUIChatEndpointTransport: ChatTransport {
  public func sendMessages(
    _ options: ChatTransportSendMessagesOptions
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    // Cancellation is handled via Swift task cancellation; `cancellationToken` is currently unused.
    // This mirrors AIKit's existing `ChatSessionInit.requestStream` hook shape.
    try await requestStream(
      chatID: options.chatID,
      messages: options.messages,
      trigger: options.trigger,
      messageID: options.messageID,
      options: options.options
    )
  }

  public func reconnectToStream(
    _ options: ChatTransportReconnectToStreamOptions
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>? {
    try await reconnectToStream(chatID: options.chatID, options: options.options)
  }
}
