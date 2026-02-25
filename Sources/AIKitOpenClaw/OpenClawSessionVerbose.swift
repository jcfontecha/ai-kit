import Foundation
import AIKitProviders

func getVerboseLevel(for sessionKey: String, client: OpenClawGatewayClient) async throws -> String? {
  let res = try await client.request(method: "chat.history", params: .object(["sessionKey": .string(sessionKey)]))
  guard case let .object(obj) = res else { return nil }
  return obj["verboseLevel"]?.stringValue
}

func setVerboseLevel(_ verbose: String, for sessionKey: String, client: OpenClawGatewayClient) async throws {
  _ = try await client.request(
    method: "sessions.patch",
    params: .object([
      "key": .string(sessionKey),
      "verboseLevel": .string(verbose),
    ])
  )
}

func clearVerboseLevel(for sessionKey: String, client: OpenClawGatewayClient) async throws {
  _ = try await client.request(
    method: "sessions.patch",
    params: .object([
      "key": .string(sessionKey),
      "verboseLevel": .null,
    ])
  )
}

