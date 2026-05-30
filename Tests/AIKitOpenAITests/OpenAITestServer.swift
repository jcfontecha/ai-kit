import Foundation
import AIKitProviders
@testable import AIKitOpenAI

final class OpenAITestServer: @unchecked Sendable {
  private let lock = NSLock()
  enum ResponseType {
    case jsonValue(JSONValue)
    case streamChunks([String])
    case error(JSONValue)
  }

  struct ResponseConfig {
    var type: ResponseType
    var status: Int
    var headers: [String: String]

    init(type: ResponseType, status: Int = 200, headers: [String: String] = [:]) {
      self.type = type
      self.status = status
      self.headers = headers
    }
  }

  struct CallRecord {
    var requestBody: String
    var requestBodyJSON: JSONValue?
    var requestHeaders: [String: String]
  }

  final class URLConfig {
    var response: ResponseConfig?
    var calls: [CallRecord] = []
  }

  var urls: [String: URLConfig] = [:]
  var calls: [CallRecord] = []

  init(config: [String: ResponseConfig]) {
    for (url, response) in config {
      let urlConfig = URLConfig()
      urlConfig.response = response
      urls[url] = urlConfig
    }
  }

  func transport() -> HTTPTransport {
    TestTransport(server: self)
  }

  private final class TestTransport: @unchecked Sendable, HTTPTransport {
    let server: OpenAITestServer
    init(server: OpenAITestServer) {
      self.server = server
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let (data, response) = try await respond(for: request, stream: false)
      return (data, response)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
      let (data, response) = try await respond(for: request, stream: true)
      let stream = AsyncThrowingStream<UInt8, Error> { continuation in
        Task {
          for byte in data {
            continuation.yield(byte)
          }
          continuation.finish()
        }
      }
      return (stream, response)
    }

    private func respond(for request: URLRequest, stream: Bool) async throws -> (Data, HTTPURLResponse) {
      guard let url = request.url?.absoluteString else {
        throw OpenAIInvalidResponseError(message: "Missing request URL.")
      }
      guard let urlConfig = server.urlConfig(for: url) else {
        throw OpenAIInvalidResponseError(message: "No response configured for \(url)")
      }

      let bodyData = request.httpBody ?? Data()
      let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
      let bodyJSON = try? OpenAIJSON.decoder.decode(JSONValue.self, from: bodyData)
      var headers: [String: String] = [:]
      for (key, value) in (request.allHTTPHeaderFields ?? [:]) {
        headers[key.lowercased()] = value
      }

      let callRecord = CallRecord(
        requestBody: bodyString,
        requestBodyJSON: bodyJSON,
        requestHeaders: headers
      )

      server.recordCall(callRecord)
      server.recordURLCall(url, callRecord)

      guard let responseConfig = urlConfig.response else {
        throw OpenAIInvalidResponseError(message: "No response configured for \(url)")
      }

      let data: Data
      switch responseConfig.type {
      case .jsonValue(let json):
        data = try OpenAIJSON.encodeToData(json)
      case .error(let json):
        data = try OpenAIJSON.encodeToData(json)
      case .streamChunks(let chunks):
        let joined = chunks.joined()
        data = joined.data(using: .utf8) ?? Data()
      }

      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: responseConfig.status,
        httpVersion: nil,
        headerFields: responseConfig.headers
      )!

      return (data, response)
    }
  }

  private func urlConfig(for url: String) -> URLConfig? {
    lock.lock()
    defer { lock.unlock() }
    return urls[url]
  }

  private func recordCall(_ record: CallRecord) {
    lock.lock()
    defer { lock.unlock() }
    calls.append(record)
  }

  private func recordURLCall(_ url: String, _ record: CallRecord) {
    lock.lock()
    defer { lock.unlock() }
    urls[url]?.calls.append(record)
  }
}

func collectStream<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
  var values: [T] = []
  for try await value in stream {
    values.append(value)
  }
  return values
}

extension OpenAITestServer {
  static let chatURL = "https://api.openai.com/v1/chat/completions"
  static let embeddingsURL = "https://api.openai.com/v1/embeddings"
  static let responsesURL = "https://api.openai.com/v1/responses"

  func responsesModel(
    _ modelId: OpenAIResponsesModelID,
    options: OpenAIResponsesProviderOptions = .init()
  ) -> OpenAIResponsesLanguageModel {
    OpenAIResponsesLanguageModel(
      modelId: modelId,
      options: options,
      config: OpenAIResponsesConfig(
        provider: "openai.responses",
        headers: { ["Authorization": "Bearer test-api-key"] },
        url: { path in "https://api.openai.com/v1\(path)" },
        transport: transport()
      )
    )
  }

  func chatModel(_ modelId: OpenAIChatModelID, options: OpenAIChatLanguageModelOptions = .init()) -> OpenAIChatLanguageModel {
    OpenAIChatLanguageModel(
      modelId: modelId,
      options: options,
      config: OpenAIChatConfig(
        provider: "openai.chat",
        headers: { ["Authorization": "Bearer test-api-key"] },
        url: { path in "https://api.openai.com/v1\(path)" },
        transport: transport()
      )
    )
  }

  func embeddingModel(_ modelId: OpenAIEmbeddingModelID, settings: OpenAIEmbeddingSettings = .init()) -> OpenAIEmbeddingModel {
    OpenAIEmbeddingModel(
      modelId: modelId,
      settings: settings,
      config: OpenAIEmbeddingConfig(
        provider: "openai.embedding",
        headers: { ["Authorization": "Bearer test-api-key"] },
        url: { path in "https://api.openai.com/v1\(path)" },
        transport: transport()
      )
    )
  }
}
