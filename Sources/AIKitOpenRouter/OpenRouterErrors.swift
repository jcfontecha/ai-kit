import Foundation
import AIKitProviders

struct OpenRouterAPIError: LocalizedError, Equatable {
  struct UpstreamError: Sendable, Equatable {
    let message: String
    let type: String?
    let code: String?
    let param: String?
  }

  let message: String
  let statusCode: Int?
  let provider: String?
  let upstream: UpstreamError?
  let debugDetails: String?

  var errorDescription: String? { message }

  init(
    message: String,
    statusCode: Int?,
    provider: String? = nil,
    upstream: UpstreamError? = nil,
    debugDetails: String? = nil
  ) {
    self.message = message
    self.statusCode = statusCode
    self.provider = provider
    self.upstream = upstream
    self.debugDetails = debugDetails
  }
}

private func jsonScalarDebugString(_ value: JSONValue) -> String {
  switch value {
  case .string(let s):
    return s
  case .number(let n):
    if n.rounded(FloatingPointRoundingRule.towardZero) == n {
      return String(Int64(n))
    }
    return String(n)
  case .bool(let b):
    return b ? "true" : "false"
  case .null:
    return "null"
  case .array:
    return "<array>"
  case .object:
    return "<object>"
  }
}

private func parseUpstreamError(from raw: String) -> OpenRouterAPIError.UpstreamError? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }

  guard case let .object(envelope) = (try? OpenRouterJSON.decoder.decode(JSONValue.self, from: data)),
        case let .object(error) = envelope["error"] else {
    return nil
  }

  guard case let .string(message) = error["message"], message.isEmpty == false else { return nil }

  let type: String? = {
    guard case let .string(type) = error["type"], type.isEmpty == false else { return nil }
    return type
  }()
  let code: String? = {
    guard let code = error["code"] else { return nil }
    let value = jsonScalarDebugString(code)
    return value.isEmpty ? nil : value
  }()
  let param: String? = {
    guard let param = error["param"] else { return nil }
    let value = jsonScalarDebugString(param)
    return value.isEmpty ? nil : value
  }()

  return .init(message: message, type: type, code: code, param: param)
}

func openRouterAPIError(statusCode: Int, data: Data) -> OpenRouterAPIError {
  struct ErrorEnvelope: Decodable {
    let error: OpenRouterErrorPayload
  }

  if let decoded = try? OpenRouterJSON.decoder.decode(ErrorEnvelope.self, from: data) {
    let provider: String? = {
      if let providerName = decoded.error.metadata?["provider_name"],
         case let .string(name) = providerName,
         name.isEmpty == false {
        return name
      }
      return nil
    }()

    let upstream: OpenRouterAPIError.UpstreamError? = {
      if let raw = decoded.error.metadata?["raw"],
         case let .string(rawMessage) = raw,
         rawMessage.isEmpty == false {
        return parseUpstreamError(from: rawMessage)
      }
      return nil
    }()

    let debugDetails: String? = {
      if let raw = decoded.error.metadata?["raw"],
         case let .string(rawMessage) = raw,
         rawMessage.isEmpty == false {
        return rawMessage
      }
      return nil
    }()

    var suffixParts: [String] = []
    if let provider { suffixParts.append("provider=\(provider)") }

    let primaryType = upstream?.type ?? decoded.error.type
    if let primaryType, primaryType.isEmpty == false {
      suffixParts.append("type=\(primaryType)")
    }

    let primaryCode = upstream?.code ?? decoded.error.code.map(jsonScalarDebugString)
    if let primaryCode, primaryCode.isEmpty == false {
      suffixParts.append("code=\(primaryCode)")
    }

    let primaryParam = upstream?.param ?? decoded.error.param.map(jsonScalarDebugString)
    if let primaryParam, primaryParam.isEmpty == false {
      suffixParts.append("param=\(primaryParam)")
    }

    let suffix = suffixParts.isEmpty ? "" : " (\(suffixParts.joined(separator: ", ")))"
    let primaryMessage = upstream?.message ?? decoded.error.message
    return OpenRouterAPIError(
      message: "OpenRouter API error: \(statusCode): \(primaryMessage)\(suffix)",
      statusCode: statusCode,
      provider: provider,
      upstream: upstream,
      debugDetails: debugDetails
    )
  }

  if let text = String(data: data, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines),
    text.isEmpty == false {
    let truncated = String(text.prefix(300))
    return OpenRouterAPIError(
      message: "OpenRouter API error: \(statusCode): \(truncated)",
      statusCode: statusCode,
      provider: nil,
      upstream: nil,
      debugDetails: text
    )
  }

  return OpenRouterAPIError(
    message: "OpenRouter API error: \(statusCode)",
    statusCode: statusCode,
    provider: nil,
    upstream: nil,
    debugDetails: nil
  )
}

func openRouterAPIError(
  statusCode: Int,
  bytes: AsyncThrowingStream<UInt8, Error>,
  limit: Int = 64 * 1024
) async -> OpenRouterAPIError {
  var data = Data()
  do {
    for try await byte in bytes {
      data.append(byte)
      if data.count >= limit { break }
    }
  } catch {
    return OpenRouterAPIError(
      message: "OpenRouter API error: \(statusCode) (failed reading body: \(error.localizedDescription))",
      statusCode: statusCode,
      provider: nil,
      upstream: nil,
      debugDetails: nil
    )
  }
  return openRouterAPIError(statusCode: statusCode, data: data)
}

struct OpenRouterInvalidResponseError: LocalizedError, Equatable {
  let message: String

  var errorDescription: String? { message }
}

struct OpenRouterInvalidArgumentError: LocalizedError, Equatable {
  let message: String

  var errorDescription: String? { message }
}

struct OpenRouterUnsupportedFunctionalityError: LocalizedError, Equatable {
  let functionality: String

  var errorDescription: String? {
    "Unsupported functionality: \(functionality)"
  }
}
