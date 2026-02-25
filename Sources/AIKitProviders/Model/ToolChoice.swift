import Foundation

public enum ToolChoice: Sendable, Equatable {
  case auto
  case none
  case required
  case tool(name: String)
}

