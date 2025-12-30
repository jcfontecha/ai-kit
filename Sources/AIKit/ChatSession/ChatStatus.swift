import Foundation

public enum ChatStatus: Sendable, Equatable {
  case submitted
  case streaming
  case ready
  case error
}
