import Foundation
import AIKitProviders

public enum GenerateImagePrompt: Sendable, Equatable {
  case text(String)
  case multimodal(text: String? = nil, images: [DataContent], mask: DataContent? = nil)
}

public struct GenerateImageOptions: Sendable {
  public var model: any ImageModel
  public var prompt: GenerateImagePrompt

  public var n: Int
  public var maxImagesPerCall: Int?
  public var size: String?
  public var aspectRatio: String?
  public var seed: Int?

  public var providerOptions: ProviderOptions?
  public var headers: [String: String]?
  public var maxRetries: Int
  public var cancellationToken: CancellationToken?

  public init(
    model: any ImageModel,
    prompt: GenerateImagePrompt,
    n: Int = 1,
    maxImagesPerCall: Int? = nil,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    headers: [String: String]? = nil,
    maxRetries: Int = 2,
    cancellationToken: CancellationToken? = nil
  ) {
    self.model = model
    self.prompt = prompt
    self.n = n
    self.maxImagesPerCall = maxImagesPerCall
    self.size = size
    self.aspectRatio = aspectRatio
    self.seed = seed
    self.providerOptions = providerOptions
    self.headers = headers
    self.maxRetries = maxRetries
    self.cancellationToken = cancellationToken
  }
}

public struct GenerateImageResult: Sendable {
  public var images: [GeneratedFile]
  public var warnings: [CallWarning]
  public var responses: [ImageModelResponseMetadata]
  public var providerMetadata: ProviderMetadata
  public var usage: ImageUsage

  public init(
    images: [GeneratedFile],
    warnings: [CallWarning] = [],
    responses: [ImageModelResponseMetadata] = [],
    providerMetadata: ProviderMetadata = [:],
    usage: ImageUsage = .init()
  ) {
    self.images = images
    self.warnings = warnings
    self.responses = responses
    self.providerMetadata = providerMetadata
    self.usage = usage
  }

  public var image: GeneratedFile { images[0] }
}

public func generateImage(_ options: GenerateImageOptions) async throws -> GenerateImageResult {
  let maxRetries = try normalizeMaxRetries(options.maxRetries)

  let modelMaxImagesPerCall = await options.model.maxImagesPerCall()
  let maxImagesPerCall = options.maxImagesPerCall ?? modelMaxImagesPerCall ?? 1
  let desiredCount = max(options.n, 0)

  let callCount = Int(ceil(Double(desiredCount) / Double(maxImagesPerCall)))
  let callImageCounts: [Int] = (0..<callCount).map { index in
    if index < callCount - 1 { return maxImagesPerCall }
    let remainder = desiredCount % maxImagesPerCall
    return remainder == 0 ? maxImagesPerCall : remainder
  }

  let promptNormalized = try normalizePrompt(options.prompt)

  var results: [ImageResponse] = []
  results.reserveCapacity(callImageCounts.count)
  for count in callImageCounts {
    let result = try await retry(maxRetries: maxRetries, cancellationToken: options.cancellationToken) {
      try await options.model.generate(
        ImageRequest(
          prompt: promptNormalized.prompt,
          files: promptNormalized.files,
          mask: promptNormalized.mask,
          n: count,
          size: options.size,
          aspectRatio: options.aspectRatio,
          seed: options.seed,
          providerOptions: options.providerOptions ?? [:],
          headers: options.headers,
          cancellationToken: options.cancellationToken
        )
      )
    }
    results.append(result)
  }

  var images: [GeneratedFile] = []
  var warnings: [CallWarning] = []
  var responses: [ImageModelResponseMetadata] = []
  var providerMetadata: ProviderMetadata = [:]
  var totalUsage = ImageUsage()

  for result in results {
    images.append(contentsOf: result.images.map(toGeneratedFile))
    warnings.append(contentsOf: result.warnings)
    responses.append(result.response)

    if let usage = result.usage {
      totalUsage = addImageUsage(totalUsage, usage)
    }

    if let metadata = result.providerMetadata {
      providerMetadata = mergeProviderMetadata(providerMetadata, metadata)
    }
  }

  if images.isEmpty {
    throw NoImageGeneratedError(responses: responses)
  }

  return GenerateImageResult(
    images: images,
    warnings: warnings,
    responses: responses,
    providerMetadata: providerMetadata,
    usage: totalUsage
  )
}

public func generateImage(
  model: any ImageModel,
  prompt: GenerateImagePrompt,
  n: Int = 1,
  maxImagesPerCall: Int? = nil,
  size: String? = nil,
  aspectRatio: String? = nil,
  seed: Int? = nil,
  providerOptions: ProviderOptions? = nil,
  headers: [String: String]? = nil,
  maxRetries: Int = 2,
  cancellationToken: CancellationToken? = nil
) async throws -> GenerateImageResult {
  try await generateImage(
    .init(
      model: model,
      prompt: prompt,
      n: n,
      maxImagesPerCall: maxImagesPerCall,
      size: size,
      aspectRatio: aspectRatio,
      seed: seed,
      providerOptions: providerOptions,
      headers: headers,
      maxRetries: maxRetries,
      cancellationToken: cancellationToken
    )
  )
}

private func normalizeMaxRetries(_ value: Int) throws -> Int {
  guard value >= 0 else {
    throw AIKitError.invalidConfiguration("maxRetries must be >= 0")
  }
  return value
}

private func retry<T>(
  maxRetries: Int,
  cancellationToken: CancellationToken?,
  _ operation: @Sendable () async throws -> T
) async throws -> T {
  var attempt = 0
  while true {
    if let cancellationToken, await cancellationToken.isCancelled {
      throw CancellationError()
    }
    do {
      return try await operation()
    } catch {
      if attempt >= maxRetries { throw error }
      attempt += 1
      continue
    }
  }
}

private func addImageUsage(_ lhs: ImageUsage, _ rhs: ImageUsage) -> ImageUsage {
  .init(
    inputTokens: addTokenCounts(lhs.inputTokens, rhs.inputTokens),
    outputTokens: addTokenCounts(lhs.outputTokens, rhs.outputTokens),
    totalTokens: addTokenCounts(lhs.totalTokens, rhs.totalTokens)
  )
}

private func addTokenCounts(_ a: Int?, _ b: Int?) -> Int? {
  if a == nil, b == nil { return nil }
  return (a ?? 0) + (b ?? 0)
}

private struct NormalizedPrompt: Sendable {
  var prompt: String?
  var files: [ImageRequest.File]?
  var mask: ImageRequest.File?
}

private func normalizePrompt(_ prompt: GenerateImagePrompt) throws -> NormalizedPrompt {
  switch prompt {
  case .text(let text):
    return .init(prompt: text, files: nil, mask: nil)
  case .multimodal(let text, let images, let mask):
    return .init(
      prompt: text,
      files: try images.map(toImageRequestFile),
      mask: try mask.map(toImageRequestFile)
    )
  }
}

private func toImageRequestFile(_ content: DataContent) throws -> ImageRequest.File {
  switch content {
  case .url(let url):
    if url.scheme?.lowercased() == "data" {
      let parsed = try splitDataURL(url.absoluteString)
      guard let base64 = parsed.base64, let data = Data(base64Encoded: base64) else {
        throw AIKitError.invalidConfiguration("Invalid data URL format: \(url.absoluteString)")
      }
      let detected = detectImageMediaType(data: data)
      return .file(data: data, mediaType: parsed.mediaType ?? detected ?? "image/png")
    }

    if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
      return .url(url)
    }

    // Unknown URL schemes are treated as a URL reference for the provider.
    return .url(url)

  case .base64(let base64):
    guard let data = Data(base64Encoded: base64) else {
      throw AIKitError.invalidConfiguration("Invalid base64 image content.")
    }
    return .file(data: data, mediaType: detectImageMediaType(data: data) ?? "image/png")

  case .data(let data):
    return .file(data: data, mediaType: detectImageMediaType(data: data) ?? "image/png")
  }
}

private func toGeneratedFile(_ data: ImageResponse.ImageData) -> GeneratedFile {
  switch data {
  case .data(let bytes):
    return .init(data: bytes, mediaType: detectImageMediaType(data: bytes) ?? "image/png")
  case .base64(let base64):
    let bytes = Data(base64Encoded: base64) ?? Data()
    return .init(data: bytes, mediaType: detectImageMediaType(data: bytes) ?? "image/png")
  }
}

private func mergeProviderMetadata(_ current: ProviderMetadata, _ incoming: ProviderMetadata) -> ProviderMetadata {
  var result = current

  for (providerName, metadataValue) in incoming {
    if providerName == "gateway" {
      result[providerName] = mergeGatewayMetadata(current: result[providerName], incoming: metadataValue)
      if case .object(let object) = result[providerName],
         case .array(let imagesValue) = object["images"],
         imagesValue.isEmpty {
        var updated = object
        updated.removeValue(forKey: "images")
        result[providerName] = .object(updated)
      }
      continue
    }

    result[providerName] = mergeNonGatewayMetadata(current: result[providerName], incoming: metadataValue)
  }

  return result
}

private func mergeGatewayMetadata(current: JSONValue?, incoming: JSONValue) -> JSONValue {
  guard case .object(let incomingObject) = incoming else { return incoming }
  guard let current, case .object(let currentObject) = current else { return .object(incomingObject) }
  return .object(currentObject.merging(incomingObject, uniquingKeysWith: { _, new in new }))
}

private func mergeNonGatewayMetadata(current: JSONValue?, incoming: JSONValue) -> JSONValue {
  guard case .object(let incomingObject) = incoming else { return incoming }

  var mergedObject: [String: JSONValue] = [:]
  if let current, case .object(let currentObject) = current {
    mergedObject = currentObject
  }

  let currentImages: [JSONValue] = {
    guard case .array(let value) = mergedObject["images"] else { return [] }
    return value
  }()

  let incomingImages: [JSONValue] = {
    guard case .array(let value) = incomingObject["images"] else { return [] }
    return value
  }()

  mergedObject = mergedObject.merging(incomingObject, uniquingKeysWith: { _, new in new })
  mergedObject["images"] = .array(currentImages + incomingImages)

  return .object(mergedObject)
}

private func detectImageMediaType(data: Data) -> String? {
  let bytes = [UInt8](data)
  if bytes.count >= 8,
     bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
     bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
    return "image/png"
  }
  if bytes.count >= 3,
     bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
    return "image/jpeg"
  }
  if bytes.count >= 6 {
    let header = String(bytes: bytes.prefix(6), encoding: .ascii)
    if header == "GIF87a" || header == "GIF89a" {
      return "image/gif"
    }
  }
  if bytes.count >= 12 {
    let riff = String(bytes: bytes.prefix(4), encoding: .ascii)
    let webp = String(bytes: bytes.dropFirst(8).prefix(4), encoding: .ascii)
    if riff == "RIFF" && webp == "WEBP" {
      return "image/webp"
    }
  }
  return nil
}

private func splitDataURL(_ urlString: String) throws -> (mediaType: String?, base64: String?) {
  guard let commaIndex = urlString.firstIndex(of: ",") else {
    return (nil, nil)
  }

  let header = String(urlString[..<commaIndex])
  let content = String(urlString[urlString.index(after: commaIndex)...])

  let mediaType = header
    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
    .first?
    .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
    .last
    .map(String.init)

  return (mediaType, content.isEmpty ? nil : content)
}
