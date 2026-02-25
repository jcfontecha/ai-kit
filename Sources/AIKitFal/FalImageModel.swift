import Foundation
import AIKitProviders

struct FalImageModelConfig: Sendable {
  var baseURL: String
  var apiKey: String?
  var headers: @Sendable () -> [String: String]
  var transport: HTTPTransport
  var currentDate: @Sendable () -> Date

  init(
    baseURL: String,
    apiKey: String?,
    headers: @escaping @Sendable () -> [String: String],
    transport: HTTPTransport,
    currentDate: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.headers = headers
    self.transport = transport
    self.currentDate = currentDate
  }
}

struct FalImageModel: ImageModel, Sendable {
  let id: String
  let config: FalImageModelConfig

  init(modelId: String, config: FalImageModelConfig) {
    self.id = modelId
    self.config = config
  }

  func maxImagesPerCall() async -> Int? { 1 }

  func generate(_ request: ImageRequest) async throws -> ImageResponse {
    var warnings: [CallWarning] = []

    var requestBody: [String: JSONValue] = [
      "num_images": .number(Double(request.n)),
    ]

    if let prompt = request.prompt {
      requestBody["prompt"] = .string(prompt)
    }
    if let seed = request.seed {
      requestBody["seed"] = .number(Double(seed))
    }

    if let size = request.size {
      if let parsed = parseSize(size) {
        requestBody["image_size"] = .object([
          "width": .number(Double(parsed.width)),
          "height": .number(Double(parsed.height)),
        ])
      }
    } else if let aspectRatio = request.aspectRatio {
      if let imageSize = convertAspectRatioToFalImageSize(aspectRatio) {
        requestBody["image_size"] = imageSize
      }
    }

    if let files = request.files, files.isEmpty == false {
      requestBody["image_url"] = .string(try convertFileToDataURI(files[0]))
      if files.count > 1 {
        warnings.append(
          .init(
            message: "fal.ai only supports a single input image. Additional images are ignored.",
            code: "other"
          )
        )
      }
    }

    if let mask = request.mask {
      requestBody["mask_url"] = .string(try convertFileToDataURI(mask))
    }

    let (falOptions, deprecatedKeys) = parseFalProviderOptions(request.providerOptions["fal"] ?? [:])
    if deprecatedKeys.isEmpty == false {
      warnings.append(.init(message: deprecatedSnakeCaseWarningMessage(deprecatedKeys), code: "other"))
    }

    let fieldMapping: [String: String] = [
      "imageUrl": "image_url",
      "maskUrl": "mask_url",
      "guidanceScale": "guidance_scale",
      "numInferenceSteps": "num_inference_steps",
      "enableSafetyChecker": "enable_safety_checker",
      "outputFormat": "output_format",
      "syncMode": "sync_mode",
      "safetyTolerance": "safety_tolerance",
    ]

    for (key, value) in falOptions {
      let apiKey = fieldMapping[key] ?? key
      requestBody[apiKey] = value
    }

    let urlString = "\(config.baseURL)/\(id)"
    var headers = combineHeaders([config.headers(), request.headers])
    headers["content-type"] = "application/json"

    var urlRequest = URLRequest(url: URL(string: urlString)!)
    urlRequest.httpMethod = "POST"
    for (key, value) in headers {
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }
    urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(requestBody))

    let now = config.currentDate()
    let (data, response) = try await config.transport.data(for: urlRequest)
    if (200..<300).contains(response.statusCode) == false {
      throw FalAPIError(
        message: parseFalErrorMessage(from: data) ?? "Unknown fal error",
        statusCode: response.statusCode,
        url: urlString
      )
    }

    let responseJSON = try JSONDecoder().decode(JSONValue.self, from: data)
    let parsed = try parseFalImageResponse(responseJSON)

    var images: [ImageResponse.ImageData] = []
    images.reserveCapacity(parsed.images.count)
    for image in parsed.images {
      var getRequest = URLRequest(url: URL(string: image.url)!)
      getRequest.httpMethod = "GET"
      let (bytes, getResponse) = try await config.transport.data(for: getRequest)
      if (200..<300).contains(getResponse.statusCode) == false {
        throw FalAPIError(message: "Failed to download image.", statusCode: getResponse.statusCode, url: image.url)
      }
      images.append(.data(bytes))
    }

    let providerMetadata = buildFalProviderMetadata(
      images: parsed.images,
      responseMeta: parsed.meta,
      hasNSFWConcepts: parsed.hasNSFWConcepts,
      nsfwContentDetected: parsed.nsfwContentDetected
    )

    return ImageResponse(
      images: images,
      warnings: warnings,
      response: .init(timestamp: now, modelID: id, headers: flattenHeaders(response)),
      providerMetadata: ["fal": providerMetadata]
    )
  }
}

struct FalAPIError: Error, Sendable, Equatable {
  var message: String
  var statusCode: Int
  var url: String
}

private struct FalParsedImage {
  var url: String
  var raw: [String: JSONValue]
}

private struct FalParsedResponse {
  var images: [FalParsedImage]
  var meta: [String: JSONValue]
  var hasNSFWConcepts: [Bool]?
  var nsfwContentDetected: [Bool]?
}

private func parseFalImageResponse(_ json: JSONValue) throws -> FalParsedResponse {
  guard case .object(let obj) = json else {
    throw AIKitError.invalidConfiguration("Invalid fal.ai response.")
  }

  let imagesValue: JSONValue? = {
    if let images = obj["images"] { return images }
    if let image = obj["image"] { return .array([image]) }
    return nil
  }()

  guard case .array(let imageItems)? = imagesValue else {
    throw AIKitError.invalidConfiguration("Invalid fal.ai response: missing images.")
  }

  var images: [FalParsedImage] = []
  images.reserveCapacity(imageItems.count)

  for item in imageItems {
    guard case .object(let imageObj) = item,
          case .string(let url)? = imageObj["url"] else {
      throw AIKitError.invalidConfiguration("Invalid fal.ai response: invalid image item.")
    }
    images.append(.init(url: url, raw: imageObj))
  }

  var meta = obj
  meta.removeValue(forKey: "images")
  meta.removeValue(forKey: "image")
  meta.removeValue(forKey: "prompt")

  let hasNSFWConcepts = extractBoolArray(obj["has_nsfw_concepts"])
  let nsfwContentDetected = extractBoolArray(obj["nsfw_content_detected"])
  meta.removeValue(forKey: "has_nsfw_concepts")
  meta.removeValue(forKey: "nsfw_content_detected")

  return .init(
    images: images,
    meta: meta,
    hasNSFWConcepts: hasNSFWConcepts,
    nsfwContentDetected: nsfwContentDetected
  )
}

private func buildFalProviderMetadata(
  images: [FalParsedImage],
  responseMeta: [String: JSONValue],
  hasNSFWConcepts: [Bool]?,
  nsfwContentDetected: [Bool]?
) -> JSONValue {
  var fal: [String: JSONValue] = responseMeta

  let imageMetadata: [JSONValue] = images.enumerated().map { index, image in
    var raw = image.raw

    let contentType = raw.removeValue(forKey: "content_type")
    let fileName = raw.removeValue(forKey: "file_name")
    let fileData = raw.removeValue(forKey: "file_data")
    let fileSize = raw.removeValue(forKey: "file_size")
    raw.removeValue(forKey: "url")

    var meta: [String: JSONValue] = raw

    if let contentType { meta["contentType"] = contentType }
    if let fileName { meta["fileName"] = fileName }
    if let fileData { meta["fileData"] = fileData }
    if let fileSize { meta["fileSize"] = fileSize }

    let nsfw: Bool? = hasNSFWConcepts?[safe: index] ?? nsfwContentDetected?[safe: index]
    if let nsfw { meta["nsfw"] = .bool(nsfw) }

    return .object(meta)
  }

  fal["images"] = .array(imageMetadata)
  return .object(fal)
}

private func parseFalErrorMessage(from data: Data) -> String? {
  guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
        case .object(let obj) = json else { return nil }

  if case .array(let detail)? = obj["detail"] {
    let lines: [String] = detail.compactMap { item in
      guard case .object(let d) = item else { return nil }
      let locParts: [String] = {
        guard case .array(let loc)? = d["loc"] else { return [] }
        return loc.compactMap { part in
          if case .string(let s) = part { return s }
          return nil
        }
      }()
      guard case .string(let msg)? = d["msg"] else { return nil }
      let loc = locParts.joined(separator: ".")
      return loc.isEmpty ? msg : "\(loc): \(msg)"
    }
    if lines.isEmpty == false {
      return lines.joined(separator: "\n")
    }
  }

  if case .string(let message)? = obj["message"] { return message }
  return nil
}

private func parseFalProviderOptions(_ options: [String: JSONValue]) -> (options: [String: JSONValue], deprecatedKeys: [String]) {
  var result: [String: JSONValue] = [:]
  var deprecatedKeys: [String] = []

  func mapKey(_ snake: String, _ camel: String) {
    let snakeValue = options[snake]
    let camelValue = options[camel]

    if let snakeValue, snakeValue != .null {
      deprecatedKeys.append(snake)
      result[camel] = snakeValue
    } else if let camelValue, camelValue != .null {
      result[camel] = camelValue
    }
  }

  mapKey("image_url", "imageUrl")
  mapKey("mask_url", "maskUrl")
  mapKey("guidance_scale", "guidanceScale")
  mapKey("num_inference_steps", "numInferenceSteps")
  mapKey("enable_safety_checker", "enableSafetyChecker")
  mapKey("output_format", "outputFormat")
  mapKey("sync_mode", "syncMode")
  mapKey("safety_tolerance", "safetyTolerance")

  if let strength = options["strength"], strength != .null { result["strength"] = strength }
  if let acceleration = options["acceleration"], acceleration != .null { result["acceleration"] = acceleration }

  let known: Set<String> = [
    "imageUrl", "maskUrl", "guidanceScale", "numInferenceSteps", "enableSafetyChecker", "outputFormat", "syncMode",
    "strength", "acceleration", "safetyTolerance",
    "image_url", "mask_url", "guidance_scale", "num_inference_steps", "enable_safety_checker", "output_format",
    "sync_mode", "safety_tolerance",
  ]

  for (key, value) in options where known.contains(key) == false {
    result[key] = value
  }

  return (result, deprecatedKeys)
}

private func deprecatedSnakeCaseWarningMessage(_ keys: [String]) -> String {
  let mapped = keys.map { key in
    let camel = snakeToCamel(key)
    return "'\(key)' (use '\(camel)')"
  }.joined(separator: ", ")

  return "The following provider options use deprecated snake_case and will be removed in @ai-sdk/fal v2.0. Please use camelCase instead: \(mapped)"
}

private func snakeToCamel(_ value: String) -> String {
  var result = ""
  var uppercaseNext = false
  for ch in value {
    if ch == "_" {
      uppercaseNext = true
      continue
    }
    if uppercaseNext {
      result.append(String(ch).uppercased())
      uppercaseNext = false
    } else {
      result.append(ch)
    }
  }
  return result
}

private func parseSize(_ value: String) -> (width: Int, height: Int)? {
  let parts = value.split(separator: "x")
  guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
  return (w, h)
}

private func convertAspectRatioToFalImageSize(_ aspectRatio: String) -> JSONValue? {
  switch aspectRatio {
  case "1:1":
    return .string("square_hd")
  case "16:9":
    return .string("landscape_16_9")
  case "9:16":
    return .string("portrait_16_9")
  case "4:3":
    return .string("landscape_4_3")
  case "3:4":
    return .string("portrait_4_3")
  case "16:10":
    return .object(["width": .number(1280), "height": .number(800)])
  case "10:16":
    return .object(["width": .number(800), "height": .number(1280)])
  case "21:9":
    return .object(["width": .number(2560), "height": .number(1080)])
  case "9:21":
    return .object(["width": .number(1080), "height": .number(2560)])
  default:
    return nil
  }
}

private func convertFileToDataURI(_ file: ImageRequest.File) throws -> String {
  switch file {
  case .url(let url):
    return url.absoluteString
  case .file(let data, let mediaType):
    return "data:\(mediaType);base64,\(data.base64EncodedString())"
  }
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

private func extractBoolArray(_ value: JSONValue?) -> [Bool]? {
  guard case .array(let items)? = value else { return nil }
  var result: [Bool] = []
  result.reserveCapacity(items.count)
  for item in items {
    if case .bool(let b) = item {
      result.append(b)
    } else {
      return nil
    }
  }
  return result
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard index >= 0, index < count else { return nil }
    return self[index]
  }
}
