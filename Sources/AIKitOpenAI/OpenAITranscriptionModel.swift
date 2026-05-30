import Foundation
import AIKitProviders

struct OpenAITranscriptionConfig: Sendable {
  var provider: String
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
}

struct OpenAITranscriptionModel: TranscriptionModel, Sendable {
  let id: String
  let modelId: OpenAITranscriptionModelID
  let config: OpenAITranscriptionConfig

  init(modelId: OpenAITranscriptionModelID, config: OpenAITranscriptionConfig) {
    self.modelId = modelId
    self.config = config
    self.id = modelId.rawValue
  }

  func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResponse {
    let options = request.providerOptions?["openai"] ?? [:]

    var form = OpenAIMultipartForm()
    form.addField(name: "model", value: modelId.rawValue)

    let mediaType = request.mediaType ?? "audio/wav"
    form.addFile(
      name: "file",
      filename: "audio.\(audioFileExtension(for: mediaType))",
      contentType: mediaType,
      data: request.audio
    )

    for key in ["language", "prompt", "response_format", "temperature"] {
      if let value = options[key], let field = transcriptionFieldValue(value) {
        form.addField(name: key, value: field)
      }
    }

    var urlRequest = URLRequest(url: URL(string: config.url("/audio/transcriptions"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = form.encode()

    var headers = config.headers()
    headers["content-type"] = form.contentType
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (data, response) = try await config.transport.data(for: urlRequest)
    guard response.statusCode == 200 else {
      throw openAIAPIError(statusCode: response.statusCode, data: data)
    }

    let decoded = try OpenAIJSON.decoder.decode(OpenAITranscriptionResponse.self, from: data)
    return TranscriptionResponse(text: decoded.text, modelID: modelId.rawValue)
  }
}

private func transcriptionFieldValue(_ value: JSONValue) -> String? {
  switch value {
  case .string(let s):
    return s
  case .number(let n):
    if n.rounded(.towardZero) == n {
      return String(Int64(n))
    }
    return String(n)
  case .bool(let b):
    return b ? "true" : "false"
  case .null, .array, .object:
    return nil
  }
}

private func audioFileExtension(for mediaType: String) -> String {
  switch mediaType.lowercased() {
  case "audio/mpeg", "audio/mp3": return "mp3"
  case "audio/wav", "audio/x-wav": return "wav"
  case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
  case "audio/webm": return "webm"
  case "audio/ogg": return "ogg"
  case "audio/flac": return "flac"
  default:
    if let slash = mediaType.firstIndex(of: "/") {
      return String(mediaType[mediaType.index(after: slash)...])
    }
    return "wav"
  }
}

private struct OpenAITranscriptionResponse: Decodable {
  var text: String
}
