import Foundation
import AIKitProviders

struct ReplicateImageModelConfig: Sendable {
  var baseURL: String
  var headers: @Sendable () -> [String: String]
  var transport: HTTPTransport
  var currentDate: @Sendable () -> Date
  var predictionPollIntervalNanoseconds: UInt64
  var predictionPollTimeoutSeconds: TimeInterval

  init(
    baseURL: String,
    headers: @escaping @Sendable () -> [String: String],
    transport: HTTPTransport,
    currentDate: @escaping @Sendable () -> Date = { Date() },
    predictionPollIntervalNanoseconds: UInt64 = 2_000_000_000,
    predictionPollTimeoutSeconds: TimeInterval = 35 * 60
  ) {
    self.baseURL = baseURL
    self.headers = headers
    self.transport = transport
    self.currentDate = currentDate
    self.predictionPollIntervalNanoseconds = predictionPollIntervalNanoseconds
    self.predictionPollTimeoutSeconds = predictionPollTimeoutSeconds
  }
}

struct ReplicateImageModel: ImageModel, Sendable {
  let id: String
  let config: ReplicateImageModelConfig
  private var isFlux2Model: Bool { id.hasPrefix("black-forest-labs/flux-2-") }
  private var isNanoBananaModel: Bool { id.hasPrefix("google/nano-banana") }
  private var isOpenAIGPTImageModel: Bool { id == "openai/gpt-image-1.5" || id == "openai/gpt-image-2" }
  private var isIdeogramModel: Bool { id.hasPrefix("ideogram-ai/") }

  init(modelId: String, config: ReplicateImageModelConfig) {
    self.id = modelId
    self.config = config
  }

  func maxImagesPerCall() async -> Int? {
    if isOpenAIGPTImageModel { return 10 }
    if isFlux2Model { return 8 }
    return 1
  }

  func generate(_ request: ImageRequest) async throws -> ImageResponse {
    var warnings: [CallWarning] = []

    let (modelId, version) = splitModelId(id)
    let now = config.currentDate()

    let replicateOptions = request.providerOptions["replicate"] ?? [:]
    let maxWaitTimeInSeconds: Double? = {
      guard case .number(let value)? = replicateOptions["maxWaitTimeInSeconds"] else { return nil }
      return value
    }()

    var inputOptions = replicateOptions
    inputOptions.removeValue(forKey: "maxWaitTimeInSeconds")

    var imageInputs: [String: JSONValue] = [:]
    if let files = request.files, files.isEmpty == false {
      if isOpenAIGPTImageModel {
        // openai/gpt-image-* expects: input_images: [uri...]
        imageInputs["input_images"] = .array(try files.map { .string(try convertFileToDataURI($0)) })
      } else if isNanoBananaModel {
        // Nano Banana models expect: image_input: [uri...]
        imageInputs["image_input"] = .array(try files.map { .string(try convertFileToDataURI($0)) })
      } else if isFlux2Model {
        // black-forest-labs/flux-2-* expects: input_image, input_image_2... (max 8)
        let maxCount = 8
        let capped = Array(files.prefix(maxCount))
        for (idx, file) in capped.enumerated() {
          let key = idx == 0 ? "input_image" : "input_image_\(idx + 1)"
          imageInputs[key] = .string(try convertFileToDataURI(file))
        }
        if files.count > maxCount {
          warnings.append(
            .init(
              message: "Flux-2 models support up to 8 input images. Additional images are ignored.",
              code: "other"
            )
          )
        }
      } else {
        // Default: many Replicate models accept a single `image` input.
        imageInputs["image"] = .string(try convertFileToDataURI(files[0]))
        if files.count > 1 {
          warnings.append(
            .init(
              message: "This Replicate model only supports a single input image. Additional images are ignored.",
              code: "other"
            )
          )
        }
      }
    }

    var maskInput: JSONValue?
    if let mask = request.mask {
      if isFlux2Model {
        warnings.append(
          .init(
            message: "Flux-2 models do not support mask input. The mask will be ignored.",
            code: "other"
          )
        )
      } else if isOpenAIGPTImageModel {
        warnings.append(
          .init(
            message: "openai/gpt-image models do not support mask input. The mask will be ignored.",
            code: "other"
          )
        )
      } else {
        maskInput = .string(try convertFileToDataURI(mask))
      }
    }

    // Ideogram models use a structured `json_prompt` (supplied via providerOptions) and
    // reject requests that include both `prompt` and `json_prompt` ("Supply exactly one").
    let usesJSONPrompt = isIdeogramModel && inputOptions["json_prompt"] != nil
    var input: [String: JSONValue] = [:]
    if usesJSONPrompt == false {
      input["prompt"] = .string(request.prompt ?? "")
    }
    if isOpenAIGPTImageModel {
      input["number_of_images"] = .number(Double(request.n))
    } else if isNanoBananaModel == false, isIdeogramModel == false {
      input["num_outputs"] = .number(Double(request.n))
    }
    if let aspectRatio = request.aspectRatio {
      input["aspect_ratio"] = .string(aspectRatio)
    }
    if let size = request.size, isOpenAIGPTImageModel == false, isNanoBananaModel == false {
      input["size"] = .string(size)
    }
    if let seed = request.seed, isOpenAIGPTImageModel == false, isNanoBananaModel == false, isIdeogramModel == false {
      input["seed"] = .number(Double(seed))
    }

    for (key, value) in imageInputs {
      input[key] = value
    }
    if let maskInput {
      input["mask"] = maskInput
    }
    for (key, value) in inputOptions {
      input[key] = value
    }

    var body: [String: JSONValue] = [
      "input": .object(input),
    ]
    if let version {
      body["version"] = .string(version)
    }

    let prefer: [String: String] = {
      if let maxWaitTimeInSeconds {
        let formatted: String
        if maxWaitTimeInSeconds.rounded(.down) == maxWaitTimeInSeconds {
          formatted = String(Int(maxWaitTimeInSeconds))
        } else {
          formatted = String(maxWaitTimeInSeconds)
        }
        return ["prefer": "wait=\(formatted)"]
      }
      return ["prefer": "wait"]
    }()

    func requestJSON(
      method: String,
      urlString: String,
      body: [String: JSONValue]? = nil,
      extraHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
      var headers = combineHeaders([config.headers(), request.headers, extraHeaders])
      if body != nil {
        headers["content-type"] = "application/json"
      }

      var urlRequest = URLRequest(url: URL(string: urlString)!)
      urlRequest.httpMethod = method
      for (key, value) in headers {
        urlRequest.setValue(value, forHTTPHeaderField: key)
      }
      if let body {
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
      }
      return try await config.transport.data(for: urlRequest)
    }

    func fetchLatestVersionID(modelRef: String) async throws -> String {
      let urlString = "\(config.baseURL)/models/\(modelRef)/versions"
      let (data, response) = try await requestJSON(method: "GET", urlString: urlString, extraHeaders: prefer)
      if (200..<300).contains(response.statusCode) == false {
        throw ReplicateAPIError(
          message: parseReplicateErrorMessage(from: data) ?? "Unknown Replicate error",
          statusCode: response.statusCode,
          headers: flattenHeaders(response)
        )
      }

      let json = try JSONDecoder().decode(JSONValue.self, from: data)
      guard case .object(let obj) = json else {
        throw AIKitError.invalidConfiguration("Invalid Replicate versions response.")
      }
      guard case .array(let results)? = obj["results"], let first = results.first,
            case .object(let versionObj) = first,
            case .string(let id)? = versionObj["id"],
            id.isEmpty == false else {
        throw AIKitError.invalidConfiguration("Replicate model has no versions.")
      }
      return id
    }

    let urlString =
      version != nil
        ? "\(config.baseURL)/predictions"
        : "\(config.baseURL)/models/\(modelId)/predictions"

    let (data, response) = try await requestJSON(method: "POST", urlString: urlString, body: body, extraHeaders: prefer)

    let resolved: (Data, HTTPURLResponse) = try await {
      // Replicate HTTP API: `/models/{owner}/{name}/predictions` only works for "official models".
      // For other models, use `POST /predictions` and include a version.
      if response.statusCode == 404, version == nil {
        let latestVersionID = try await fetchLatestVersionID(modelRef: modelId)
        var updatedBody = body
        updatedBody["version"] = .string(latestVersionID)
        let url = "\(config.baseURL)/predictions"
        return try await requestJSON(method: "POST", urlString: url, body: updatedBody, extraHeaders: prefer)
      }
      return (data, response)
    }()

    if (200..<300).contains(resolved.1.statusCode) == false {
      throw ReplicateAPIError(
        message: parseReplicateErrorMessage(from: resolved.0) ?? "Unknown Replicate error",
        statusCode: resolved.1.statusCode,
        headers: flattenHeaders(resolved.1)
      )
    }

    let finalResponse = try await waitForTerminalPrediction(initial: resolved)
    let responseJSON = try JSONDecoder().decode(JSONValue.self, from: finalResponse.data)
    let outputURLs = try extractOutputURLs(from: responseJSON)

    var images: [ImageResponse.ImageData] = []
    images.reserveCapacity(outputURLs.count)
    for url in outputURLs {
      var getRequest = URLRequest(url: URL(string: url)!)
      getRequest.httpMethod = "GET"
      let (bytes, _) = try await config.transport.data(for: getRequest)
      images.append(.data(bytes))
    }

    return ImageResponse(
      images: images,
      warnings: warnings,
      response: .init(
        timestamp: now,
        modelID: id,
        headers: flattenHeaders(finalResponse.response)
      )
    )
  }

  private func waitForTerminalPrediction(
    initial: (data: Data, response: HTTPURLResponse)
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    let snapshot = predictionSnapshot(from: initial.data, response: initial.response)

    if snapshot.outputURLs.isEmpty == false || snapshot.status == .succeeded {
      return initial
    }

    switch snapshot.status {
    case .failed, .canceled:
      throw ReplicateAPIError(
        message: predictionFailureMessage(snapshot: snapshot, fallbackData: initial.data),
        statusCode: initial.response.statusCode,
        headers: flattenHeaders(initial.response)
      )
    case .starting, .processing, .none:
      guard let getURL = snapshot.getURL else {
        throw AIKitError.invalidConfiguration(
          "Replicate prediction is still processing, but the API did not return a status URL."
        )
      }
      return try await pollPrediction(getURL: getURL)
    case .succeeded:
      return initial
    }
  }

  private func pollPrediction(getURL: URL) async throws -> (data: Data, response: HTTPURLResponse) {
    let deadline = Date().addingTimeInterval(config.predictionPollTimeoutSeconds)

    while true {
      try Task.checkCancellation()
      if Date() >= deadline {
        throw AIKitError.invalidConfiguration("Replicate prediction timed out while processing.")
      }

      if config.predictionPollIntervalNanoseconds > 0 {
        try await Task.sleep(nanoseconds: config.predictionPollIntervalNanoseconds)
      }

      let result = try await requestPrediction(getURL: getURL)
      let snapshot = predictionSnapshot(from: result.data, response: result.response, fallbackGetURL: getURL)
      if snapshot.outputURLs.isEmpty == false || snapshot.status == .succeeded {
        return result
      }

      switch snapshot.status {
      case .failed, .canceled:
        throw ReplicateAPIError(
          message: predictionFailureMessage(snapshot: snapshot, fallbackData: result.data),
          statusCode: result.response.statusCode,
          headers: flattenHeaders(result.response)
        )
      case .starting, .processing, .none:
        continue
      case .succeeded:
        return result
      }
    }
  }

  private func requestPrediction(getURL: URL) async throws -> (data: Data, response: HTTPURLResponse) {
    var request = URLRequest(url: getURL)
    request.httpMethod = "GET"
    for (key, value) in config.headers() {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let (data, response) = try await config.transport.data(for: request)
    if (200..<300).contains(response.statusCode) == false {
      throw ReplicateAPIError(
        message: parseReplicateErrorMessage(from: data) ?? "Unknown Replicate error",
        statusCode: response.statusCode,
        headers: flattenHeaders(response)
      )
    }
    return (data, response)
  }
}

private struct ReplicateAPIError: Error, Sendable, Equatable {
  var message: String
  var statusCode: Int
  var headers: [String: String]
}

private func splitModelId(_ modelId: String) -> (modelId: String, version: String?) {
  let parts = modelId.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
  if parts.count == 2 {
    return (String(parts[0]), String(parts[1]))
  }
  return (modelId, nil)
}

private func convertFileToDataURI(_ file: ImageRequest.File) throws -> String {
  switch file {
  case .url(let url):
    return url.absoluteString
  case .file(let data, let mediaType):
    let base64 = data.base64EncodedString()
    return "data:\(mediaType);base64,\(base64)"
  }
}

private struct PredictionSnapshot: Equatable {
  enum Status: String, Equatable {
    case starting
    case processing
    case succeeded
    case failed
    case canceled
  }

  var id: String?
  var status: Status?
  var outputURLs: [String]
  var getURL: URL?
  var errorMessage: String?
  var logs: String?
}

private func predictionSnapshot(
  from data: Data,
  response: HTTPURLResponse? = nil,
  fallbackGetURL: URL? = nil
) -> PredictionSnapshot {
  let json = try? JSONDecoder().decode(JSONValue.self, from: data)
  guard case .object(let object) = json else {
    return .init(
      id: nil,
      status: nil,
      outputURLs: [],
      getURL: fallbackGetURL ?? predictionGetURL(from: response, predictionID: nil),
      errorMessage: parseReplicateErrorMessage(from: data),
      logs: nil
    )
  }

  let id: String? = {
    guard case .string(let value)? = object["id"], value.isEmpty == false else { return nil }
    return value
  }()
  let status: PredictionSnapshot.Status? = {
    guard case .string(let value)? = object["status"] else { return nil }
    return .init(rawValue: value)
  }()
  let getURL: URL? = {
    if case .object(let urls)? = object["urls"],
       case .string(let value)? = urls["get"],
       let url = URL(string: value) {
      return url
    }
    if let fallbackGetURL {
      return fallbackGetURL
    }
    return predictionGetURL(from: response, predictionID: id)
  }()
  let outputURLs = (try? extractOutputURLs(from: .object(object))) ?? []

  let errorMessage: String? = {
    if case .string(let value)? = object["error"], value.isEmpty == false {
      return value
    }
    return parseReplicateErrorMessage(from: data)
  }()
  let logs: String? = {
    guard case .string(let value)? = object["logs"], value.isEmpty == false else { return nil }
    return value
  }()

  return .init(
    id: id,
    status: status,
    outputURLs: outputURLs,
    getURL: getURL,
    errorMessage: errorMessage,
    logs: logs
  )
}

private func predictionGetURL(from response: HTTPURLResponse?, predictionID: String?) -> URL? {
  if let location = response?.value(forHTTPHeaderField: "Location"), let url = URL(string: location) {
    return url
  }
  guard let predictionID, let baseURL = response?.url else { return nil }
  return URL(string: "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "api.replicate.com")/v1/predictions/\(predictionID)")
}

private func extractOutputURLs(from json: JSONValue) throws -> [String] {
  guard case .object(let obj) = json else {
    throw AIKitError.invalidConfiguration("Invalid Replicate response.")
  }
  guard let output = obj["output"] else {
    throw AIKitError.invalidConfiguration("Invalid Replicate response: missing output.")
  }
  switch output {
  case .string(let value):
    return [value]
  case .array(let values):
    return values.compactMap { value in
      if case .string(let s) = value { return s }
      return nil
    }
  default:
    throw AIKitError.invalidConfiguration("Invalid Replicate response: invalid output type.")
  }
}

private func predictionFailureMessage(snapshot: PredictionSnapshot, fallbackData: Data) -> String {
  let base = snapshot.errorMessage ?? parseReplicateErrorMessage(from: fallbackData) ?? "Replicate prediction failed."
  guard let logs = snapshot.logs?.trimmingCharacters(in: .whitespacesAndNewlines), logs.isEmpty == false else {
    return base
  }
  return "\(base)\n\nReplicate logs:\n\(logs)"
}

private func parseReplicateErrorMessage(from data: Data) -> String? {
  guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
        case .object(let obj) = json else { return nil }
  if case .string(let detail)? = obj["detail"] { return detail }
  if case .string(let error)? = obj["error"] { return error }
  return nil
}

private func flattenHeaders(_ response: HTTPURLResponse) -> [String: String] {
  var headers: [String: String] = [:]
  for (key, value) in response.allHeaderFields {
    let keyString = String(describing: key).lowercased()
    let valueString = String(describing: value)
    headers[keyString] = valueString
  }
  return headers
}
