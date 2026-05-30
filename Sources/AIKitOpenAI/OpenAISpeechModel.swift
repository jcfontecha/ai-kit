import Foundation
import AIKitProviders

struct OpenAISpeechConfig: Sendable {
  var provider: String
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
}

struct OpenAISpeechModel: SpeechModel, Sendable {
  let id: String
  let modelId: OpenAISpeechModelID
  let config: OpenAISpeechConfig

  init(modelId: OpenAISpeechModelID, config: OpenAISpeechConfig) {
    self.modelId = modelId
    self.config = config
    self.id = modelId.rawValue
  }

  func speak(_ request: SpeechRequest) async throws -> SpeechResponse {
    let options = request.providerOptions?["openai"] ?? [:]

    var body: [String: JSONValue] = [
      "model": .string(modelId.rawValue),
      "input": .string(request.text),
    ]

    if case .string(let voice)? = options["voice"] {
      body["voice"] = .string(voice)
    } else {
      body["voice"] = .string("alloy")
    }
    if case .string(let format)? = options["response_format"] {
      body["response_format"] = .string(format)
    }
    if case .number(let speed)? = options["speed"] {
      body["speed"] = .number(speed)
    }
    if case .string(let instructions)? = options["instructions"] {
      body["instructions"] = .string(instructions)
    }

    var urlRequest = URLRequest(url: URL(string: config.url("/audio/speech"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = try OpenAIJSON.encodeToData(.object(body))

    var headers = config.headers()
    headers["content-type"] = "application/json"
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (data, response) = try await config.transport.data(for: urlRequest)
    guard response.statusCode == 200 else {
      throw openAIAPIError(statusCode: response.statusCode, data: data)
    }

    return SpeechResponse(audio: data, modelID: modelId.rawValue)
  }
}
