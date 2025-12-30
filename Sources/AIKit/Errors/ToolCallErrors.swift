import Foundation

public struct NoSuchToolError: Error, Sendable, Equatable {
  public var message: String
  public init(message: String) {
    self.message = message
  }
}

public struct InvalidToolInputError: Error, Sendable, Equatable {
  public var message: String
  public init(message: String) {
    self.message = message
  }
}

public struct ToolCallRepairFailedError: Error, Sendable, Equatable {
  public var message: String
  public init(message: String) {
    self.message = message
  }
}

public enum ToolCallError: Sendable, Equatable {
  case noSuchTool(NoSuchToolError)
  case invalidInput(InvalidToolInputError)
  case repairFailed(ToolCallRepairFailedError)

  public var message: String {
    switch self {
    case .noSuchTool(let error): return error.message
    case .invalidInput(let error): return error.message
    case .repairFailed(let error): return error.message
    }
  }
}

