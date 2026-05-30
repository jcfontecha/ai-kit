import Foundation
import AIKitProviders

struct OpenAIAPIError: LocalizedError, Equatable {
  let message: String
  let statusCode: Int?
  let type: String?
  let code: String?
  let param: String?

  var errorDescription: String? { message }

  init(
    message: String,
    statusCode: Int?,
    type: String? = nil,
    code: String? = nil,
    param: String? = nil
  ) {
    self.message = message
    self.statusCode = statusCode
    self.type = type
    self.code = code
    self.param = param
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

func openAIAPIError(statusCode: Int, data: Data) -> OpenAIAPIError {
  struct ErrorEnvelope: Decodable {
    let error: OpenAIErrorPayload
  }

  if let decoded = try? OpenAIJSON.decoder.decode(ErrorEnvelope.self, from: data) {
    var suffixParts: [String] = []

    if let type = decoded.error.type, type.isEmpty == false {
      suffixParts.append("type=\(type)")
    }

    let code = decoded.error.code.map(jsonScalarDebugString)
    if let code, code.isEmpty == false {
      suffixParts.append("code=\(code)")
    }

    let param = decoded.error.param.map(jsonScalarDebugString)
    if let param, param.isEmpty == false {
      suffixParts.append("param=\(param)")
    }

    let suffix = suffixParts.isEmpty ? "" : " (\(suffixParts.joined(separator: ", ")))"
    return OpenAIAPIError(
      message: "OpenAI API error: \(statusCode): \(decoded.error.message)\(suffix)",
      statusCode: statusCode,
      type: decoded.error.type,
      code: code,
      param: param
    )
  }

  if let text = String(data: data, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines),
    text.isEmpty == false {
    let truncated = String(text.prefix(300))
    return OpenAIAPIError(
      message: "OpenAI API error: \(statusCode): \(truncated)",
      statusCode: statusCode
    )
  }

  return OpenAIAPIError(
    message: "OpenAI API error: \(statusCode)",
    statusCode: statusCode
  )
}

func openAIAPIError(
  statusCode: Int,
  bytes: AsyncThrowingStream<UInt8, Error>,
  limit: Int = 64 * 1024
) async -> OpenAIAPIError {
  var data = Data()
  do {
    for try await byte in bytes {
      data.append(byte)
      if data.count >= limit { break }
    }
  } catch {
    return OpenAIAPIError(
      message: "OpenAI API error: \(statusCode) (failed reading body: \(error.localizedDescription))",
      statusCode: statusCode
    )
  }
  return openAIAPIError(statusCode: statusCode, data: data)
}

struct OpenAIErrorPayload: Decodable {
  var code: JSONValue?
  var message: String
  var type: String?
  var param: JSONValue?

  enum CodingKeys: String, CodingKey {
    case code
    case message
    case type
    case param
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    message = (try? container.decode(String.self, forKey: .message)) ?? ""
    code = try? container.decode(JSONValue.self, forKey: .code)
    type = try? container.decode(String.self, forKey: .type)
    param = try? container.decode(JSONValue.self, forKey: .param)
  }
}

struct OpenAIInvalidResponseError: LocalizedError, Equatable {
  let message: String

  var errorDescription: String? { message }
}

struct OpenAIInvalidArgumentError: LocalizedError, Equatable {
  let message: String

  var errorDescription: String? { message }
}

struct OpenAIUnsupportedFunctionalityError: LocalizedError, Equatable {
  let functionality: String

  var errorDescription: String? {
    "Unsupported functionality: \(functionality)"
  }
}
