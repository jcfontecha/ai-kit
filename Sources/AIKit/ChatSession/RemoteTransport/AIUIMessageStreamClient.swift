import Foundation
import AIKitProviders

public enum AIUIMessageStreamClientError: Error, LocalizedError, Sendable, Equatable {
  case missingOrInvalidHeader(actual: String?)

  public var errorDescription: String? {
    switch self {
    case .missingOrInvalidHeader(let actual):
      if let actual {
        return "Expected `x-vercel-ai-ui-message-stream: v1` but got `\(actual)`."
      }
      return "Missing required header `x-vercel-ai-ui-message-stream: v1`."
    }
  }
}

public struct AIUIMessageStreamClient: Sendable {
  public var transport: any HTTPTransport
  public var decoder: SSEUIMessageStreamDecoder

  public init(
    transport: any HTTPTransport,
    decoder: SSEUIMessageStreamDecoder = .init()
  ) {
    self.transport = transport
    self.decoder = decoder
  }

  public func streamParts(for request: URLRequest) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    let (bytes, response) = try await transport.bytes(for: request)
    try Self.validateUIMessageStreamHeader(response)
    return decoder.decode(bytes)
  }

  public static func validateUIMessageStreamHeader(_ response: HTTPURLResponse) throws {
    let headerName = "x-vercel-ai-ui-message-stream"
    let value = response.value(forHTTPHeaderField: headerName)
    guard value == "v1" else {
      throw AIUIMessageStreamClientError.missingOrInvalidHeader(actual: value)
    }
  }
}
