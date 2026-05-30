import Foundation

public enum MCPError: LocalizedError, Equatable {
  /// Transport-level failure (non-2xx HTTP status, missing response).
  case transport(statusCode: Int, body: String)
  /// The response could not be understood as a JSON-RPC message.
  case invalidResponse(String)
  /// The server returned a JSON-RPC error object.
  case rpc(code: Int, message: String)
  /// A call was made before `connect()` completed.
  case notConnected

  public var errorDescription: String? {
    switch self {
    case let .transport(statusCode, body):
      return "MCP transport error (HTTP \(statusCode)): \(body)"
    case let .invalidResponse(detail):
      return "MCP invalid response: \(detail)"
    case let .rpc(code, message):
      return "MCP error \(code): \(message)"
    case .notConnected:
      return "MCP client is not connected. Call connect() first."
    }
  }
}
