import Foundation

public struct Usage: Sendable, Codable, Equatable {
  public struct InputTokens: Sendable, Codable, Equatable {
    public var total: Int?
    public var noCache: Int?
    public var cacheRead: Int?
    public var cacheWrite: Int?

    public init(total: Int? = nil, noCache: Int? = nil, cacheRead: Int? = nil, cacheWrite: Int? = nil) {
      self.total = total
      self.noCache = noCache
      self.cacheRead = cacheRead
      self.cacheWrite = cacheWrite
    }
  }

  public struct OutputTokens: Sendable, Codable, Equatable {
    public var total: Int?
    public var text: Int?
    public var reasoning: Int?

    public init(total: Int? = nil, text: Int? = nil, reasoning: Int? = nil) {
      self.total = total
      self.text = text
      self.reasoning = reasoning
    }
  }

  public var inputTokens: InputTokens?
  public var outputTokens: OutputTokens?

  public init(inputTokens: InputTokens? = nil, outputTokens: OutputTokens? = nil) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }
}
