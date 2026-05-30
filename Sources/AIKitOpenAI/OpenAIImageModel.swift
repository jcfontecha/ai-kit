import Foundation
import AIKitProviders

struct OpenAIImageConfig: Sendable {
  var provider: String
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
  var currentDate: @Sendable () -> Date

  init(
    provider: String,
    headers: @escaping @Sendable () -> [String: String],
    url: @escaping @Sendable (String) -> String,
    transport: HTTPTransport,
    currentDate: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.provider = provider
    self.headers = headers
    self.url = url
    self.transport = transport
    self.currentDate = currentDate
  }
}

struct OpenAIImageModel: ImageModel, Sendable {
  let id: String
  let modelId: OpenAIImageModelID
  let config: OpenAIImageConfig

  init(modelId: OpenAIImageModelID, config: OpenAIImageConfig) {
    self.modelId = modelId
    self.config = config
    self.id = modelId.rawValue
  }

  func maxImagesPerCall() async -> Int? {
    switch modelId.rawValue {
    case "dall-e-3":
      return 1
    case "dall-e-2":
      return 10
    default:
      // gpt-image-1 / gpt-image-2 and other gpt-image variants support batching.
      if modelId.rawValue.hasPrefix("gpt-image") {
        return 10
      }
      return 1
    }
  }

  func generate(_ request: ImageRequest) async throws -> ImageResponse {
    var warnings: [CallWarning] = []

    if request.aspectRatio != nil {
      warnings.append(
        .init(
          message: "OpenAI image models do not support `aspectRatio`. Use `size` instead.",
          code: "unsupported-setting"
        )
      )
    }

    let openAIOptions = request.providerOptions["openai"] ?? [:]
    let now = config.currentDate()

    let hasImageInput = (request.files?.isEmpty == false) || request.mask != nil

    if hasImageInput {
      return try await generateEdit(
        request: request,
        openAIOptions: openAIOptions,
        warnings: warnings,
        now: now
      )
    }

    return try await generate(
      request: request,
      openAIOptions: openAIOptions,
      warnings: warnings,
      now: now
    )
  }

  private func generate(
    request: ImageRequest,
    openAIOptions: [String: JSONValue],
    warnings: [CallWarning],
    now: Date
  ) async throws -> ImageResponse {
    var body: [String: JSONValue] = [
      "model": .string(modelId.rawValue),
      "n": .number(Double(request.n)),
      "response_format": .string("b64_json"),
    ]
    if let prompt = request.prompt {
      body["prompt"] = .string(prompt)
    }
    if let size = request.size {
      body["size"] = .string(size)
    }
    if let seed = request.seed {
      body["seed"] = .number(Double(seed))
    }
    for (key, value) in openAIImageOptions(openAIOptions) {
      body[key] = value
    }

    var urlRequest = URLRequest(url: URL(string: config.url("/images/generations"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = try OpenAIJSON.encodeToData(.object(body))

    var headers = combineHeaders([config.headers(), request.headers])
    headers["content-type"] = "application/json"
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    return try await send(urlRequest, warnings: warnings, now: now)
  }

  private func generateEdit(
    request: ImageRequest,
    openAIOptions: [String: JSONValue],
    warnings: [CallWarning],
    now: Date
  ) async throws -> ImageResponse {
    var form = OpenAIMultipartForm()
    form.addField(name: "model", value: modelId.rawValue)
    form.addField(name: "n", value: String(request.n))
    if let prompt = request.prompt {
      form.addField(name: "prompt", value: prompt)
    }
    if let size = request.size {
      form.addField(name: "size", value: size)
    }
    for (key, value) in openAIImageOptions(openAIOptions) {
      if let field = multipartFieldValue(value) {
        form.addField(name: key, value: field)
      }
    }

    let files = request.files ?? []
    for (index, file) in files.enumerated() {
      let (data, mediaType) = try resolveFile(file)
      // OpenAI accepts multiple input images via repeated `image[]` fields.
      let fieldName = files.count > 1 ? "image[]" : "image"
      form.addFile(
        name: fieldName,
        filename: "image-\(index).\(fileExtension(for: mediaType))",
        contentType: mediaType,
        data: data
      )
    }

    if let mask = request.mask {
      let (data, mediaType) = try resolveFile(mask)
      form.addFile(
        name: "mask",
        filename: "mask.\(fileExtension(for: mediaType))",
        contentType: mediaType,
        data: data
      )
    }

    var urlRequest = URLRequest(url: URL(string: config.url("/images/edits"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = form.encode()

    var headers = combineHeaders([config.headers(), request.headers])
    headers["content-type"] = form.contentType
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    return try await send(urlRequest, warnings: warnings, now: now)
  }

  private func send(
    _ urlRequest: URLRequest,
    warnings: [CallWarning],
    now: Date
  ) async throws -> ImageResponse {
    let (data, response) = try await config.transport.data(for: urlRequest)
    guard response.statusCode == 200 else {
      throw openAIAPIError(statusCode: response.statusCode, data: data)
    }

    let decoded = try OpenAIJSON.decoder.decode(OpenAIImageResponse.self, from: data)
    let images = decoded.data.map { ImageResponse.ImageData.base64($0.b64JSON) }

    var providerMetadata: ProviderMetadata?
    if let usage = decoded.usage, let value = OpenAIJSON.encodeToJSONValue(usage) {
      providerMetadata = ["openai": .object(["usage": value])]
    }

    return ImageResponse(
      images: images,
      warnings: warnings,
      response: .init(
        timestamp: now,
        modelID: modelId.rawValue,
        headers: response.allHeaderFields as? [String: String]
      ),
      providerMetadata: providerMetadata
    )
  }

  private func resolveFile(_ file: ImageRequest.File) throws -> (Data, String) {
    switch file {
    case .file(let data, let mediaType):
      return (data, mediaType)
    case .url:
      throw OpenAIUnsupportedFunctionalityError(
        functionality: "URL-based image inputs for OpenAI image edits (provide raw file data instead)"
      )
    }
  }
}

/// Reads OpenAI-specific image parameters from `providerOptions["openai"]`.
private func openAIImageOptions(_ options: [String: JSONValue]) -> [String: JSONValue] {
  var result: [String: JSONValue] = [:]
  for key in ["quality", "background", "output_format", "moderation", "style", "user"] {
    if let value = options[key], value != .null {
      result[key] = value
    }
  }
  return result
}

private func multipartFieldValue(_ value: JSONValue) -> String? {
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

private func fileExtension(for mediaType: String) -> String {
  switch mediaType.lowercased() {
  case "image/png": return "png"
  case "image/jpeg", "image/jpg": return "jpg"
  case "image/webp": return "webp"
  case "image/gif": return "gif"
  default:
    if let slash = mediaType.firstIndex(of: "/") {
      return String(mediaType[mediaType.index(after: slash)...])
    }
    return "png"
  }
}

private struct OpenAIImageResponse: Decodable {
  var created: Int?
  var data: [OpenAIImageDatum]
  var usage: OpenAIImageUsage?
}

private struct OpenAIImageDatum: Decodable {
  var b64JSON: String

  enum CodingKeys: String, CodingKey {
    case b64JSON = "b64_json"
  }
}

private struct OpenAIImageUsage: Codable {
  var totalTokens: Int?
  var inputTokens: Int?
  var outputTokens: Int?

  enum CodingKeys: String, CodingKey {
    case totalTokens = "total_tokens"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
  }
}
