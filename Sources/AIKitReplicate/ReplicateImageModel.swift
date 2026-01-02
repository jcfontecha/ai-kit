import Foundation
import AIKitProviders

struct ReplicateImageModelConfig: Sendable {
  var baseURL: String
  var headers: @Sendable () -> [String: String]
  var transport: HTTPTransport
  var currentDate: @Sendable () -> Date

  init(
    baseURL: String,
    headers: @escaping @Sendable () -> [String: String],
    transport: HTTPTransport,
    currentDate: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.baseURL = baseURL
    self.headers = headers
    self.transport = transport
    self.currentDate = currentDate
  }
}

struct ReplicateImageModel: ImageModel, Sendable {
  let id: String
  let config: ReplicateImageModelConfig
  private var isFlux2Model: Bool { id.hasPrefix("black-forest-labs/flux-2-") }
  private var isNanoBanana: Bool { id == "google/nano-banana" }
  private var isOpenAIGPTImage15: Bool { id == "openai/gpt-image-1.5" }

  init(modelId: String, config: ReplicateImageModelConfig) {
    self.id = modelId
    self.config = config
  }

  func maxImagesPerCall() async -> Int? {
    if isOpenAIGPTImage15 { return 10 }
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
      if isOpenAIGPTImage15 {
        // openai/gpt-image-1.5 expects: input_images: [uri...]
        imageInputs["input_images"] = .array(try files.map { .string(try convertFileToDataURI($0)) })
      } else if isNanoBanana {
        // google/nano-banana expects: image_input: [uri...]
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
      } else if isOpenAIGPTImage15 {
        warnings.append(
          .init(
            message: "openai/gpt-image-1.5 does not support mask input. The mask will be ignored.",
            code: "other"
          )
        )
      } else {
        maskInput = .string(try convertFileToDataURI(mask))
      }
    }

    var input: [String: JSONValue] = ["prompt": .string(request.prompt ?? "")]
    if isOpenAIGPTImage15 {
      input["number_of_images"] = .number(Double(request.n))
    } else {
      input["num_outputs"] = .number(Double(request.n))
    }
    if let aspectRatio = request.aspectRatio {
      input["aspect_ratio"] = .string(aspectRatio)
    }
    if let size = request.size, isOpenAIGPTImage15 == false {
      input["size"] = .string(size)
    }
    if let seed = request.seed, isOpenAIGPTImage15 == false {
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

    let urlString =
      version != nil
        ? "\(config.baseURL)/predictions"
        : "\(config.baseURL)/models/\(modelId)/predictions"

    var headers = combineHeaders([config.headers(), request.headers, prefer])
    headers["content-type"] = "application/json"

    var urlRequest = URLRequest(url: URL(string: urlString)!)
    urlRequest.httpMethod = "POST"
    for (key, value) in headers {
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }
    urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))

    let (data, response) = try await config.transport.data(for: urlRequest)
    if (200..<300).contains(response.statusCode) == false {
      throw ReplicateAPIError(
        message: parseReplicateErrorMessage(from: data) ?? "Unknown Replicate error",
        statusCode: response.statusCode,
        headers: flattenHeaders(response)
      )
    }

    let responseJSON = try JSONDecoder().decode(JSONValue.self, from: data)
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
        headers: flattenHeaders(response)
      )
    )
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
