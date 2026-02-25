import Foundation
import AIKitProviders

private struct OpenClawRequestRouting: Sendable {
  var sessionKey: String
  var agentId: String?
  var conversationID: String?
  var threadID: String?
}

public struct OpenClawAgentLanguageModel: LanguageModel, Sendable {
  public let id: String
  public let capabilities: ModelCapabilities = [.toolCalling]
  public let supportedURLs: SupportedURLPatterns = [:]

  private let settings: OpenClawProviderSettings
  private let sessionKey: String
  private let agentId: String?
  private let conversationID: String?
  private let threadID: String?

  private let makeWebSocket: @Sendable (URL, String?) async throws -> any OpenClawWebSocket
  private let makeRequestID: @Sendable () -> String
  private let makeRunID: @Sendable () -> String

  init(
    id: String,
    settings: OpenClawProviderSettings,
    sessionKey: String,
    agentId: String?,
    conversationID: String? = nil,
    threadID: String? = nil,
    makeWebSocket: @escaping @Sendable (URL, String?) async throws -> any OpenClawWebSocket = { url, fingerprint in
      OpenClawURLSessionWebSocket(url: url, tlsFingerprintSHA256: fingerprint)
    },
    makeRequestID: @escaping @Sendable () -> String = { UUID().uuidString },
    makeRunID: @escaping @Sendable () -> String = { UUID().uuidString }
  ) {
    self.id = id
    self.settings = settings
    self.sessionKey = sessionKey
    self.agentId = agentId
    self.conversationID = conversationID
    self.threadID = threadID
    self.makeWebSocket = makeWebSocket
    self.makeRequestID = makeRequestID
    self.makeRunID = makeRunID
  }

  public func generate(_ request: ModelRequest) async throws -> ModelResponse {
    var content: [ModelContentPart] = []
    var assistantText = ""
    var finishReason: FinishReason = .other
    var rawFinishReason: String?
    var usage = Usage()
    var requestMetadata = LanguageModelRequestMetadata()
    var responseMetadata = LanguageModelResponseMetadata()
    var providerMetadata: ProviderMetadata?

    for try await part in stream(request) {
      switch part {
      case .startStep(let request, _):
        requestMetadata = request
      case .textDelta(_, let delta, _):
        assistantText += delta
      case .toolCall(let call):
        content.append(.toolCall(call))
      case .toolResult(let result):
        if result.preliminary != true {
          content.append(.toolResult(result))
        }
      case .toolError(let error):
        content.append(.toolError(error))
      case .toolOutputDenied(let denied):
        content.append(.toolOutputDenied(denied))
      case .finishStep(let response, let stepUsage, let reason, let raw, let metadata):
        responseMetadata = response
        usage = stepUsage
        finishReason = reason
        rawFinishReason = raw
        providerMetadata = metadata ?? providerMetadata
      case .finish(let reason, let totalUsage, let metadata):
        finishReason = reason
        usage = totalUsage
        providerMetadata = metadata ?? providerMetadata
      case .error(let error):
        finishReason = .error
        rawFinishReason = error.message
      default:
        continue
      }
    }

    if assistantText.isEmpty == false {
      content.append(.text(assistantText))
    }

    return ModelResponse(
      content: content,
      finishReason: finishReason,
      rawFinishReason: rawFinishReason,
      usage: usage,
      warnings: [],
      request: requestMetadata,
      response: responseMetadata,
      providerMetadata: providerMetadata
    )
  }

  public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      let clientBox = OpenClawClientBox()
      let task = Task {
        do {
          let routing = resolveRouting(for: request)
          let prepared = try prepareAgentCall(from: request)
          let runId = makeRunID()
          let textPartId = "openclaw-text-\(runId)"

          let requestBody = prepared.requestBody(
            runId: runId,
            sessionKey: routing.sessionKey,
            agentId: routing.agentId
          )
          continuation.yield(.streamStart())
          continuation.yield(.startStep(request: .init(body: .object(requestBody))))
          continuation.yield(.textStart(id: textPartId))

          let client = OpenClawGatewayClient(config: gatewayConfig())
          await clientBox.set(client)
          try await client.connect()

          let previousVerbose: String?
          do {
            previousVerbose = try await getVerboseLevel(for: routing.sessionKey, client: client)
          } catch {
            if shouldIgnoreVerboseSetupError(error) {
              previousVerbose = nil
            } else {
              throw error
            }
          }

          do {
            try await setVerboseLevel(settings.toolVerboseLevel.rawValue, for: routing.sessionKey, client: client)
          } catch {
            if shouldIgnoreVerboseSetupError(error) == false {
              throw error
            }
          }
          defer {
            let restore = settings.restoreVerboseLevelAfterRun
            Task {
              if restore {
                if let previousVerbose {
                  _ = try? await setVerboseLevel(previousVerbose, for: routing.sessionKey, client: client)
                } else {
                  _ = try? await clearVerboseLevel(for: routing.sessionKey, client: client)
                }
              }
              await client.close()
              await clientBox.set(nil)
            }
          }

          let tracker = OpenClawStreamTracker()
          let eventTask = Task {
            try await streamRunEvents(
              runId: runId,
              textPartId: textPartId,
              client: client,
              continuation: continuation,
              tracker: tracker
            )
          }
          defer { eventTask.cancel() }

          let payload = try await withThrowingTaskGroup(of: JSONValue?.self) { group in
            group.addTask {
              try await client.request(
                method: "agent",
                params: .object(prepared.params(runId: runId, sessionKey: routing.sessionKey, agentId: routing.agentId)),
                expectFinal: true
              )
            }
            group.addTask {
              try await Task.sleep(nanoseconds: UInt64(settings.requestTimeoutSeconds * 1_000_000_000))
              throw OpenClawGatewayError.remoteError(message: "timeout after \(settings.requestTimeoutSeconds)s")
            }
            let payload = (try await group.next()) ?? nil
            group.cancelAll()
            return payload
          }
          let outcome = parseFinalRunOutcome(payload: payload)
          let streamedAssistantText = await tracker.snapshotAssistantText()
          if let assistantText = outcome.assistantText?.trimmingCharacters(in: .whitespacesAndNewlines),
             assistantText.isEmpty == false {
            if streamedAssistantText.isEmpty {
              continuation.yield(.textDelta(id: textPartId, text: assistantText))
            } else if assistantText.hasPrefix(streamedAssistantText) {
              let delta = String(assistantText.dropFirst(streamedAssistantText.count))
              if delta.isEmpty == false {
                continuation.yield(.textDelta(id: textPartId, text: delta))
              }
            }
          }
          let streamedToolCallIDs = await tracker.snapshotStreamedToolCallIDs()
          for pendingToolCall in outcome.pendingToolCalls where streamedToolCallIDs.contains(pendingToolCall.id) == false {
            let toolMetadata: ProviderMetadata = [
              "openclaw": .object(["phase": .string("pending-tool-call")]),
            ]
            continuation.yield(
              .toolInputStart(
                id: pendingToolCall.id,
                toolName: pendingToolCall.name,
                providerMetadata: toolMetadata,
                providerExecuted: true
              )
            )
            continuation.yield(
              .toolInputDelta(
                id: pendingToolCall.id,
                delta: pendingToolCall.argumentsJSON,
                providerMetadata: toolMetadata
              )
            )
            continuation.yield(.toolInputEnd(id: pendingToolCall.id, providerMetadata: toolMetadata))
            continuation.yield(
              .toolCall(
                .init(
                  toolCallID: pendingToolCall.id,
                  toolName: pendingToolCall.name,
                  inputJSON: pendingToolCall.argumentsJSON,
                  input: pendingToolCall.input,
                  providerExecuted: true,
                  dynamic: true,
                  providerMetadata: toolMetadata
                )
              )
            )
          }

          let openClawMetadata = makeProviderMetadata(
            sessionKey: routing.sessionKey,
            runId: runId,
            agentID: routing.agentId,
            conversationID: routing.conversationID,
            threadID: routing.threadID
          )

          continuation.yield(.textEnd(id: textPartId))
          continuation.yield(.finishStep(
            response: .init(id: runId, modelID: id, timestamp: Date()),
            usage: outcome.usage,
            finishReason: outcome.finishReason,
            rawFinishReason: outcome.rawFinishReason,
            providerMetadata: openClawMetadata
          ))
          continuation.yield(.finish(
            finishReason: outcome.finishReason,
            usage: outcome.usage,
            providerMetadata: openClawMetadata
          ))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
        Task { await clientBox.close() }
      }
    }
  }

  private func optionString(_ options: [String: JSONValue], keys: [String]) -> String? {
    for key in keys {
      guard let value = options[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
      else {
        continue
      }
      return value
    }
    return nil
  }

  private func normalizedRoutingComponent(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    let lowered = trimmed.lowercased()
    let collapsedWhitespace = lowered.replacingOccurrences(
      of: "\\s+",
      with: "-",
      options: .regularExpression
    )
    let sanitized = collapsedWhitespace.replacingOccurrences(
      of: "[^a-z0-9:_-]+",
      with: "-",
      options: .regularExpression
    )
    let stripped = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    guard stripped.isEmpty == false else { return nil }
    return String(stripped.prefix(96))
  }

  private func resolveRouting(for request: ModelRequest) -> OpenClawRequestRouting {
    let openClawOptions = request.providerOptions?["openclaw"] ?? [:]
    let overrideSessionKey = optionString(openClawOptions, keys: ["sessionKey", "session_key"])
    let overrideAgentID = optionString(openClawOptions, keys: ["agentId", "agent_id"])
    let overrideConversationID = optionString(
      openClawOptions,
      keys: ["conversationID", "conversationId", "conversation_id"]
    )
    let overrideThreadID = optionString(openClawOptions, keys: ["threadID", "threadId", "thread_id"])

    var resolvedSessionKey = overrideSessionKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? sessionKey
    if resolvedSessionKey.isEmpty {
      resolvedSessionKey = "main"
    }

    let resolvedConversationID = overrideConversationID ?? conversationID
    if let normalizedConversation = normalizedRoutingComponent(resolvedConversationID) {
      resolvedSessionKey += ":conversation:\(normalizedConversation)"
    }

    let resolvedThreadID = overrideThreadID ?? threadID
    if let normalizedThread = normalizedRoutingComponent(resolvedThreadID) {
      resolvedSessionKey += ":thread:\(normalizedThread)"
    }

    return .init(
      sessionKey: resolvedSessionKey,
      agentId: overrideAgentID ?? agentId,
      conversationID: resolvedConversationID,
      threadID: resolvedThreadID
    )
  }

  private func makeProviderMetadata(
    sessionKey: String,
    runId: String,
    agentID: String?,
    conversationID: String?,
    threadID: String?
  ) -> ProviderMetadata {
    var openClawObject: [String: JSONValue] = [
      "sessionKey": .string(sessionKey),
      "runId": .string(runId),
    ]
    if let agentID {
      openClawObject["agentId"] = .string(agentID)
    }
    if let conversationID {
      openClawObject["conversationId"] = .string(conversationID)
    }
    if let threadID {
      openClawObject["threadId"] = .string(threadID)
    }
    return ["openclaw": .object(openClawObject)]
  }

  private func gatewayConfig() -> OpenClawGatewayClientConfig {
    OpenClawGatewayClientConfig(
      url: settings.gatewayURL,
      token: settings.token,
      password: settings.password,
      tlsFingerprintSHA256: settings.tlsFingerprintSHA256,
      clientID: settings.clientID,
      clientDisplayName: settings.clientDisplayName,
      clientVersion: settings.clientVersion,
      clientPlatform: settings.clientPlatform,
      clientMode: settings.clientMode,
      makeWebSocket: makeWebSocket,
      makeRequestID: makeRequestID
    )
  }
}

private func shouldIgnoreVerboseSetupError(_ error: Error) -> Bool {
  guard let gatewayError = error as? OpenClawGatewayError else { return false }
  if case .remoteError = gatewayError {
    return true
  }
  return false
}
