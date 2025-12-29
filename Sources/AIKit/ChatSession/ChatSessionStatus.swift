import Foundation

public enum ChatSessionStatus: Sendable, Equatable {
  case submitted
  case streaming
  case ready
  case error
}

