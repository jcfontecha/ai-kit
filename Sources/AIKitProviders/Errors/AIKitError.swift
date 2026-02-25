import Foundation

public enum AIKitError: Error, Sendable, Equatable {
  case notImplemented(String)
  case invalidConfiguration(String)
}

extension AIKitError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notImplemented(let message):
      return message
    case .invalidConfiguration(let message):
      return message
    }
  }
}
