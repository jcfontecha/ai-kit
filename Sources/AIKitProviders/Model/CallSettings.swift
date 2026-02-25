import Foundation

/// Generic model call settings that map to common provider parameters.
///
/// These settings are passed through to providers. Unsupported settings should be ignored and
/// surfaced as `CallWarning`s where possible.
public struct CallSettings: Sendable, Codable, Equatable {
  public var maxOutputTokens: Int?
  public var temperature: Double?
  public var topP: Double?
  public var topK: Int?
  public var presencePenalty: Double?
  public var frequencyPenalty: Double?
  public var stopSequences: [String]?
  public var seed: Int?

  public init(
    maxOutputTokens: Int? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    presencePenalty: Double? = nil,
    frequencyPenalty: Double? = nil,
    stopSequences: [String]? = nil,
    seed: Int? = nil
  ) {
    self.maxOutputTokens = maxOutputTokens
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.presencePenalty = presencePenalty
    self.frequencyPenalty = frequencyPenalty
    self.stopSequences = stopSequences
    self.seed = seed
  }
}

