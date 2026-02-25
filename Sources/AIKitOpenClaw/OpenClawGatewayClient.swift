import Foundation
import AIKitProviders

enum OpenClawGatewayError: Error, LocalizedError, Equatable {
  case invalidConfiguration(String)
  case invalidJSON(String)
  case remoteError(message: String, code: String? = nil, details: JSONValue? = nil)
  case disconnected

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message):
      return message
    case .invalidJSON(let message):
      return "OpenClaw gateway: invalid JSON (\(message))"
    case .remoteError(let message, let code, _):
      if let code, code.isEmpty == false {
        return "OpenClaw gateway error [\(code)]: \(message)"
      }
      return "OpenClaw gateway error: \(message)"
    case .disconnected:
      return "OpenClaw gateway: disconnected"
    }
  }
}

struct OpenClawGatewayClientConfig: Sendable {
  var url: URL
  var token: String?
  var password: String?
  var tlsFingerprintSHA256: String?

  var clientID: String
  var clientDisplayName: String?
  var clientVersion: String
  var clientPlatform: String
  var clientMode: String

  var caps: [String]
  var role: String
  var scopes: [String]

  var minProtocol: Int
  var maxProtocol: Int

  var makeWebSocket: @Sendable (URL, String?) async throws -> any OpenClawWebSocket
  var makeRequestID: @Sendable () -> String

  init(
    url: URL,
    token: String?,
    password: String?,
    tlsFingerprintSHA256: String?,
    clientID: String,
    clientDisplayName: String?,
    clientVersion: String,
    clientPlatform: String,
    clientMode: String,
    caps: [String] = ["tool-events"],
    role: String = "operator",
    scopes: [String] = ["operator.admin"],
    minProtocol: Int = 1,
    maxProtocol: Int = 999,
    makeWebSocket: @escaping @Sendable (URL, String?) async throws -> any OpenClawWebSocket = { url, fingerprint in
      OpenClawURLSessionWebSocket(url: url, tlsFingerprintSHA256: fingerprint)
    },
    makeRequestID: @escaping @Sendable () -> String = { UUID().uuidString }
  ) {
    self.url = url
    self.token = token
    self.password = password
    self.tlsFingerprintSHA256 = tlsFingerprintSHA256
    self.clientID = clientID
    self.clientDisplayName = clientDisplayName
    self.clientVersion = clientVersion
    self.clientPlatform = clientPlatform
    self.clientMode = clientMode
    self.caps = caps
    self.role = role
    self.scopes = scopes
    self.minProtocol = minProtocol
    self.maxProtocol = maxProtocol
    self.makeWebSocket = makeWebSocket
    self.makeRequestID = makeRequestID
  }
}

struct OpenClawEventFrame: Sendable, Equatable {
  var event: String
  var payload: JSONValue?
  var seq: Int?
  var stateVersion: JSONValue?
}

actor OpenClawGatewayClient {
  private struct Pending {
    var expectFinal: Bool
    var continuation: CheckedContinuation<JSONValue?, Error>
  }

  nonisolated let events: AsyncThrowingStream<OpenClawEventFrame, Error>
  private let eventsContinuation: AsyncThrowingStream<OpenClawEventFrame, Error>.Continuation

  private let config: OpenClawGatewayClientConfig
  private var ws: (any OpenClawWebSocket)?
  private var pendingByID: [String: Pending] = [:]
  private var receiveTask: Task<Void, Never>?
  private var closed = false

  init(config: OpenClawGatewayClientConfig) {
    self.config = config
    let (events, continuation) = AsyncThrowingStream.makeStream(of: OpenClawEventFrame.self)
    self.events = events
    self.eventsContinuation = continuation
  }

  func connect() async throws {
    guard closed == false else { throw OpenClawGatewayError.disconnected }
    guard ws == nil else { return }

    if config.token == nil && config.password == nil {
      throw OpenClawGatewayError.invalidConfiguration("OpenClaw gateway requires a token or password.")
    }

    let ws = try await config.makeWebSocket(config.url, config.tlsFingerprintSHA256)
    self.ws = ws
    self.receiveTask = Task { await self.receiveLoop() }

    _ = try await request(
      method: "connect",
      params: .object([
        "minProtocol": .number(Double(config.minProtocol)),
        "maxProtocol": .number(Double(config.maxProtocol)),
        "client": .object([
          "id": .string(config.clientID),
          "displayName": config.clientDisplayName.map(JSONValue.string),
          "version": .string(config.clientVersion),
          "platform": .string(config.clientPlatform),
          "mode": .string(config.clientMode),
        ].compacted()),
        "caps": .array(config.caps.map(JSONValue.string)),
        "role": .string(config.role),
        "scopes": .array(config.scopes.map(JSONValue.string)),
        "auth": .object([
          "token": config.token.map(JSONValue.string),
          "password": config.password.map(JSONValue.string),
        ].compacted()),
      ])
    )
  }

  func close() async {
    guard closed == false else { return }
    closed = true
    receiveTask?.cancel()
    receiveTask = nil
    if let ws {
      await ws.close()
    }
    ws = nil
    failAllPending(OpenClawGatewayError.disconnected)
    eventsContinuation.finish()
  }

  func request(method: String, params: JSONValue? = nil, expectFinal: Bool = false) async throws -> JSONValue? {
    guard closed == false else { throw OpenClawGatewayError.disconnected }
    guard let ws else { throw OpenClawGatewayError.disconnected }

    let id = config.makeRequestID()
    var frame: [String: JSONValue] = [
      "type": .string("req"),
      "id": .string(id),
      "method": .string(method),
    ]
    if let params {
      frame["params"] = params
    }
    let text = try OpenClawJSON.encodeToString(.object(frame))

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue?, Error>) in
      pendingByID[id] = Pending(expectFinal: expectFinal, continuation: continuation)
      Task {
        do {
          try await ws.send(text: text)
        } catch {
          await self.failPending(id: id, error: error)
        }
      }
    }
  }

  private func receiveLoop() async {
    guard let ws else { return }
    while Task.isCancelled == false && closed == false {
      do {
        let text = try await ws.receiveText()
        let json = try OpenClawJSON.decode(text)
        try await handle(json)
      } catch {
        await closeAfterReceiveLoopError(error)
        return
      }
    }
  }

  private func closeAfterReceiveLoopError(_ error: Error) async {
    if closed {
      return
    }
    closed = true
    receiveTask?.cancel()
    receiveTask = nil
    if let ws {
      await ws.close()
    }
    ws = nil
    failAllPending(error)
    eventsContinuation.finish(throwing: error)
  }

  private func handle(_ json: JSONValue) async throws {
    guard case .object(let obj) = json else { return }
    guard case .string(let type) = obj["type"] else { return }

    switch type {
    case "res":
      try handleResponse(obj)
    case "event":
      handleEvent(obj)
    default:
      return
    }
  }

  private func handleResponse(_ obj: [String: JSONValue]) throws {
    guard let id = obj["id"]?.stringValue else { return }
    guard let pending = pendingByID[id] else { return }

    let payload = obj["payload"]
    if pending.expectFinal,
       case let .object(payloadObject) = payload,
       payloadObject["status"]?.stringValue == "accepted"
    {
      return
    }

    pendingByID.removeValue(forKey: id)

    let ok = obj["ok"]?.boolValue ?? false
    if ok {
      pending.continuation.resume(returning: payload)
      return
    }

    if case let .object(err) = obj["error"] {
      let code = err["code"]?.stringValue
      let message = err["message"]?.stringValue ?? "unknown error"
      let details = err["details"]
      pending.continuation.resume(throwing: OpenClawGatewayError.remoteError(message: message, code: code, details: details))
      return
    }

    pending.continuation.resume(throwing: OpenClawGatewayError.remoteError(message: "unknown error"))
  }

  private func handleEvent(_ obj: [String: JSONValue]) {
    guard let event = obj["event"]?.stringValue else { return }
    let frame = OpenClawEventFrame(
      event: event,
      payload: obj["payload"],
      seq: obj["seq"]?.intValue,
      stateVersion: obj["stateVersion"]
    )
    eventsContinuation.yield(frame)
  }

  private func failPending(id: String, error: Error) async {
    guard let pending = pendingByID.removeValue(forKey: id) else { return }
    pending.continuation.resume(throwing: error)
  }

  private func failAllPending(_ error: Error) {
    for (_, pending) in pendingByID {
      pending.continuation.resume(throwing: error)
    }
    pendingByID.removeAll()
  }
}

private extension Dictionary where Key == String, Value == JSONValue? {
  func compacted() -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    result.reserveCapacity(count)
    for (k, v) in self {
      if let v { result[k] = v }
    }
    return result
  }
}
