import Foundation

public protocol TranscriptionModel: Sendable {
  var id: String { get }
  func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResponse
}
