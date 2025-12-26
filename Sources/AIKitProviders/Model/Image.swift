import Foundation

public struct ImageRequest: Sendable, Equatable {
  public enum File: Sendable, Equatable {
    case url(URL)
    case file(data: Data, mediaType: String)
  }

  public var prompt: String?
  public var files: [File]?
  public var mask: File?
  public var n: Int

  public var size: String?
  public var aspectRatio: String?
  public var seed: Int?

  public var providerOptions: ProviderOptions
  public var headers: [String: String]?
  public var cancellationToken: CancellationToken?

  public init(
    prompt: String?,
    files: [File]? = nil,
    mask: File? = nil,
    n: Int = 1,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions = [:],
    headers: [String: String]? = nil,
    cancellationToken: CancellationToken? = nil
  ) {
    self.prompt = prompt
    self.files = files
    self.mask = mask
    self.n = n
    self.size = size
    self.aspectRatio = aspectRatio
    self.seed = seed
    self.providerOptions = providerOptions
    self.headers = headers
    self.cancellationToken = cancellationToken
  }

  public static func == (lhs: ImageRequest, rhs: ImageRequest) -> Bool {
    lhs.prompt == rhs.prompt
      && lhs.files == rhs.files
      && lhs.mask == rhs.mask
      && lhs.n == rhs.n
      && lhs.size == rhs.size
      && lhs.aspectRatio == rhs.aspectRatio
      && lhs.seed == rhs.seed
      && lhs.providerOptions == rhs.providerOptions
      && lhs.headers == rhs.headers
  }
}

public struct ImageResponse: Sendable, Equatable {
  public enum ImageData: Sendable, Equatable {
    case data(Data)
    case base64(String)
  }

  public var images: [ImageData]
  public var warnings: [CallWarning]
  public var response: ImageModelResponseMetadata
  public var providerMetadata: ProviderMetadata?
  public var usage: ImageUsage?

  public init(
    images: [ImageData],
    warnings: [CallWarning] = [],
    response: ImageModelResponseMetadata = .init(),
    providerMetadata: ProviderMetadata? = nil,
    usage: ImageUsage? = nil
  ) {
    self.images = images
    self.warnings = warnings
    self.response = response
    self.providerMetadata = providerMetadata
    self.usage = usage
  }
}
