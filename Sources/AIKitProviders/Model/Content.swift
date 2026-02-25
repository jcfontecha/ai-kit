import Foundation

public enum DataContent: Sendable, Equatable {
  case data(Data)
  case base64(String)
  case url(URL)
}

public struct ImageContent: Sendable, Equatable {
  public var data: DataContent
  public var mediaType: String?
  public var providerOptions: ProviderOptions?

  public init(
    data: DataContent,
    mediaType: String? = nil,
    providerOptions: ProviderOptions? = nil
  ) {
    self.data = data
    self.mediaType = mediaType
    self.providerOptions = providerOptions
  }
}

public struct FileContent: Sendable, Equatable {
  public var data: DataContent
  public var filename: String?
  public var mediaType: String?
  public var providerOptions: ProviderOptions?

  public init(
    data: DataContent,
    filename: String? = nil,
    mediaType: String? = nil,
    providerOptions: ProviderOptions? = nil
  ) {
    self.data = data
    self.filename = filename
    self.mediaType = mediaType
    self.providerOptions = providerOptions
  }
}
