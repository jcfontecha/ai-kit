import Foundation
import AIKitProviders

public enum OpenClawToolVerboseLevel: String, Sendable {
  case off
  case on
  case full
}

public enum OpenClawClientID: String, Sendable {
  case webchatUI = "webchat-ui"
  case controlUI = "openclaw-control-ui"
  case webchat = "webchat"
  case cli = "cli"
  case gatewayClient = "gateway-client"
  case macOSApp = "openclaw-macos"
  case iOSApp = "openclaw-ios"
  case androidApp = "openclaw-android"
  case nodeHost = "node-host"
  case test = "test"
  case fingerprint = "fingerprint"
  case probe = "openclaw-probe"
}

public struct OpenClawProviderSettings: Sendable {
  public var gatewayURL: URL
  public var token: String?
  public var password: String?
  public var tlsFingerprintSHA256: String?

  public var sessionKey: String
  public var agentId: String?
  public var conversationID: String?
  public var threadID: String?

  /// Must be one of OpenClaw Gateway's known client IDs.
  public var clientID: String
  public var clientDisplayName: String?
  public var clientVersion: String
  public var clientPlatform: String
  public var clientMode: String

  public var toolVerboseLevel: OpenClawToolVerboseLevel
  public var restoreVerboseLevelAfterRun: Bool

  public var requestTimeoutSeconds: TimeInterval

  public init(
    gatewayURL: URL = URL(string: "ws://127.0.0.1:18789")!,
    token: String? = nil,
    password: String? = nil,
    tlsFingerprintSHA256: String? = nil,
    sessionKey: String = "main",
    agentId: String? = nil,
    conversationID: String? = nil,
    threadID: String? = nil,
    clientID: String = OpenClawClientID.iOSApp.rawValue,
    clientDisplayName: String? = nil,
    clientVersion: String = "aikit",
    clientPlatform: String = "ios",
    clientMode: String = "ui",
    toolVerboseLevel: OpenClawToolVerboseLevel = .full,
    restoreVerboseLevelAfterRun: Bool = true,
    requestTimeoutSeconds: TimeInterval = 120
  ) {
    self.gatewayURL = gatewayURL
    self.token = token
    self.password = password
    self.tlsFingerprintSHA256 = tlsFingerprintSHA256
    self.sessionKey = sessionKey
    self.agentId = agentId
    self.conversationID = conversationID
    self.threadID = threadID
    self.clientID = clientID
    self.clientDisplayName = clientDisplayName
    self.clientVersion = clientVersion
    self.clientPlatform = clientPlatform
    self.clientMode = clientMode
    self.toolVerboseLevel = toolVerboseLevel
    self.restoreVerboseLevelAfterRun = restoreVerboseLevelAfterRun
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }
}

public protocol OpenClawProvider: Sendable {
  func agent(
    sessionKey: String?,
    agentId: String?
  ) -> any LanguageModel
}

public struct OpenClawProviderClient: OpenClawProvider, Sendable {
  public let settings: OpenClawProviderSettings

  public init(settings: OpenClawProviderSettings = .init()) {
    self.settings = settings
  }

  public func agent(sessionKey: String? = nil, agentId: String? = nil) -> any LanguageModel {
    OpenClawAgentLanguageModel(
      id: "openclaw.agent",
      settings: settings,
      sessionKey: sessionKey ?? settings.sessionKey,
      agentId: agentId ?? settings.agentId,
      conversationID: settings.conversationID,
      threadID: settings.threadID
    )
  }
}

extension OpenClawProviderClient {
  public func agentsList() async throws -> OpenClawAgentsList {
    try await withGatewayConnection { client in
      let payload = try await client.request(method: "agents.list", params: .object([:]))
      guard let payload, let parsed = OpenClawAgentsList(from: payload) else {
        throw OpenClawGatewayError.invalidJSON("agents.list payload")
      }
      return parsed
    }
  }

  public func agentFileGet(agentId: String, file: String) async throws -> OpenClawAgentFile {
    let normalizedAgentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedAgentId.isEmpty == false else {
      throw OpenClawGatewayError.invalidConfiguration("OpenClaw gateway: agentId is required.")
    }

    let normalizedFile = file.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedFile.isEmpty == false else {
      throw OpenClawGatewayError.invalidConfiguration("OpenClaw gateway: file is required.")
    }

    return try await withGatewayConnection { client in
      let payload = try await client.request(
        method: "agents.files.get",
        params: .object([
          "agentId": .string(normalizedAgentId),
          "name": .string(normalizedFile),
        ])
      )
      guard let payload, let parsed = OpenClawAgentFile(from: payload) else {
        throw OpenClawGatewayError.invalidJSON("agents.files.get payload")
      }
      return parsed
    }
  }

  public func agentFileSet(agentId: String, file: String, content: String) async throws -> OpenClawAgentFile {
    let normalizedAgentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedAgentId.isEmpty == false else {
      throw OpenClawGatewayError.invalidConfiguration("OpenClaw gateway: agentId is required.")
    }

    let normalizedFile = file.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedFile.isEmpty == false else {
      throw OpenClawGatewayError.invalidConfiguration("OpenClaw gateway: file is required.")
    }

    return try await withGatewayConnection { client in
      let payload = try await client.request(
        method: "agents.files.set",
        params: .object([
          "agentId": .string(normalizedAgentId),
          "name": .string(normalizedFile),
          "content": .string(content),
        ])
      )
      guard let payload, let parsed = OpenClawAgentFile(from: payload) else {
        throw OpenClawGatewayError.invalidJSON("agents.files.set payload")
      }
      return parsed
    }
  }

  public func skillsStatus() async throws -> OpenClawSkillsStatus {
    try await withGatewayConnection { client in
      let payload = try await client.request(method: "skills.status", params: .object([:]))
      guard let payload, let parsed = OpenClawSkillsStatus(from: payload) else {
        throw OpenClawGatewayError.invalidJSON("skills.status payload")
      }
      return parsed
    }
  }
}

private extension OpenClawProviderClient {
  func withGatewayConnection<T>(
    _ operation: (OpenClawGatewayClient) async throws -> T
  ) async throws -> T {
    let client = OpenClawGatewayClient(config: gatewayConfig())
    try await client.connect()
    do {
      let result = try await operation(client)
      await client.close()
      return result
    } catch {
      await client.close()
      throw error
    }
  }

  func gatewayConfig() -> OpenClawGatewayClientConfig {
    OpenClawGatewayClientConfig(
      url: settings.gatewayURL,
      token: settings.token,
      password: settings.password,
      tlsFingerprintSHA256: settings.tlsFingerprintSHA256,
      clientID: settings.clientID,
      clientDisplayName: settings.clientDisplayName,
      clientVersion: settings.clientVersion,
      clientPlatform: settings.clientPlatform,
      clientMode: settings.clientMode
    )
  }
}

public func createOpenClaw(_ settings: OpenClawProviderSettings = .init()) -> OpenClawProviderClient {
  OpenClawProviderClient(settings: settings)
}

public let openclaw: OpenClawProviderClient = createOpenClaw()
