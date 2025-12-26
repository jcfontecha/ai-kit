import Foundation

public protocol SpeechModel: Sendable {
  var id: String { get }
  func speak(_ request: SpeechRequest) async throws -> SpeechResponse
}
