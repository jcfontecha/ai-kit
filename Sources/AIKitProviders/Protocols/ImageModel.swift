import Foundation

public protocol ImageModel: Sendable {
  var id: String { get }
  func generate(_ request: ImageRequest) async throws -> ImageResponse
  func maxImagesPerCall() async -> Int?
}

public extension ImageModel {
  func maxImagesPerCall() async -> Int? { nil }
}
