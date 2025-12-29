import Foundation

public enum AIKitError: Error, Sendable, Equatable {
  case notImplemented(String)
  case invalidConfiguration(String)
}

