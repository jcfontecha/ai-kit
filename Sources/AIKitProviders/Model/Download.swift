import Foundation

public struct DownloadRequest: Sendable, Equatable {
  public var url: URL
  public var isURLSupportedByModel: Bool

  public init(url: URL, isURLSupportedByModel: Bool) {
    self.url = url
    self.isURLSupportedByModel = isURLSupportedByModel
  }
}

public struct DownloadedAsset: Sendable, Equatable {
  public var data: Data
  public var mediaType: String?

  public init(data: Data, mediaType: String? = nil) {
    self.data = data
    self.mediaType = mediaType
  }
}

/// Experimental download hook (client-side only).
public typealias DownloadFunction = @Sendable ([DownloadRequest]) async throws -> [DownloadedAsset?]

