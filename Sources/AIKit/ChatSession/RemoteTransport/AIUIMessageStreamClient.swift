import Foundation
import AIKitProviders

public enum AIUIMessageStreamClientError: Error, LocalizedError, Sendable, Equatable {
  case missingOrInvalidHeader(actual: String?)
  case httpError(statusCode: Int, code: String?, message: String)

  public var errorDescription: String? {
    switch self {
    case .missingOrInvalidHeader(let actual):
      if let actual {
        return "Expected `x-vercel-ai-ui-message-stream: v1` but got `\(actual)`."
      }
      return "Missing required header `x-vercel-ai-ui-message-stream: v1`."
    case .httpError(_, _, let message):
      return message
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
    try await Self.validateHTTPResponse(response, bytes: bytes)
    try Self.validateUIMessageStreamHeader(response)
    return decoder.decode(bytes)
  }

  public static func validateHTTPResponse(
    _ response: HTTPURLResponse,
    bytes: AsyncThrowingStream<UInt8, Error>
  ) async throws {
    guard (200 ..< 300).contains(response.statusCode) else {
      var data = Data()
      for try await byte in bytes {
        data.append(byte)
      }
      throw httpError(statusCode: response.statusCode, data: data)
    }
  }

  public static func validateUIMessageStreamHeader(_ response: HTTPURLResponse) throws {
    let headerName = "x-vercel-ai-ui-message-stream"
    let value = response.value(forHTTPHeaderField: headerName)
    guard value == "v1" else {
      throw AIUIMessageStreamClientError.missingOrInvalidHeader(actual: value)
    }
  }

  private static func httpError(statusCode: Int, data: Data) -> AIUIMessageStreamClientError {
    if let failure = try? JSONDecoder().decode(HTTPFailureBody.self, from: data) {
      return .httpError(
        statusCode: statusCode,
        code: failure.code,
        message: failure.error
      )
    }

    let body = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return .httpError(
      statusCode: statusCode,
      code: nil,
      message: body?.isEmpty == false ? body! : "Request failed with status \(statusCode)."
    )
  }
}

private struct HTTPFailureBody: Decodable {
  let error: String
  let code: String?
}
