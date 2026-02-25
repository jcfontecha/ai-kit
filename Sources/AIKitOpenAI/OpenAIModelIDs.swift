import Foundation

public struct OpenAIChatModelID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }

  public static let o1: Self = "o1"
  public static let o1_2024_12_17: Self = "o1-2024-12-17"
  public static let o3Mini: Self = "o3-mini"
  public static let o3Mini_2025_01_31: Self = "o3-mini-2025-01-31"
  public static let o3: Self = "o3"
  public static let o3_2025_04_16: Self = "o3-2025-04-16"
  public static let gpt4_1: Self = "gpt-4.1"
  public static let gpt4_1_2025_04_14: Self = "gpt-4.1-2025-04-14"
  public static let gpt4_1Mini: Self = "gpt-4.1-mini"
  public static let gpt4_1Mini_2025_04_14: Self = "gpt-4.1-mini-2025-04-14"
  public static let gpt4_1Nano: Self = "gpt-4.1-nano"
  public static let gpt4_1Nano_2025_04_14: Self = "gpt-4.1-nano-2025-04-14"
  public static let gpt4o: Self = "gpt-4o"
  public static let gpt4o_2024_05_13: Self = "gpt-4o-2024-05-13"
  public static let gpt4o_2024_08_06: Self = "gpt-4o-2024-08-06"
  public static let gpt4o_2024_11_20: Self = "gpt-4o-2024-11-20"
  public static let gpt4oMini: Self = "gpt-4o-mini"
  public static let gpt4oMini_2024_07_18: Self = "gpt-4o-mini-2024-07-18"
  public static let gpt4Turbo: Self = "gpt-4-turbo"
  public static let gpt4Turbo_2024_04_09: Self = "gpt-4-turbo-2024-04-09"
  public static let gpt4: Self = "gpt-4"
  public static let gpt4_0613: Self = "gpt-4-0613"
  public static let gpt4_5Preview: Self = "gpt-4.5-preview"
  public static let gpt4_5Preview_2025_02_27: Self = "gpt-4.5-preview-2025-02-27"
  public static let gpt3_5Turbo_0125: Self = "gpt-3.5-turbo-0125"
  public static let gpt3_5Turbo: Self = "gpt-3.5-turbo"
  public static let gpt3_5Turbo_1106: Self = "gpt-3.5-turbo-1106"
  public static let chatgpt4oLatest: Self = "chatgpt-4o-latest"
  public static let gpt5: Self = "gpt-5"
  public static let gpt5_2025_08_07: Self = "gpt-5-2025-08-07"
  public static let gpt5Mini: Self = "gpt-5-mini"
  public static let gpt5Mini_2025_08_07: Self = "gpt-5-mini-2025-08-07"
  public static let gpt5Nano: Self = "gpt-5-nano"
  public static let gpt5Nano_2025_08_07: Self = "gpt-5-nano-2025-08-07"
  public static let gpt5ChatLatest: Self = "gpt-5-chat-latest"
  public static let gpt5_1: Self = "gpt-5.1"
  public static let gpt5_1ChatLatest: Self = "gpt-5.1-chat-latest"
  public static let gpt5_2: Self = "gpt-5.2"
  public static let gpt5_2ChatLatest: Self = "gpt-5.2-chat-latest"
  public static let gpt5_2Pro: Self = "gpt-5.2-pro"
}

public struct OpenAIResponsesModelID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }

  public static let chatgpt4oLatest: Self = "chatgpt-4o-latest"
  public static let gpt3_5Turbo_0125: Self = "gpt-3.5-turbo-0125"
  public static let gpt3_5Turbo_1106: Self = "gpt-3.5-turbo-1106"
  public static let gpt3_5Turbo: Self = "gpt-3.5-turbo"
  public static let gpt4_0613: Self = "gpt-4-0613"
  public static let gpt4Turbo_2024_04_09: Self = "gpt-4-turbo-2024-04-09"
  public static let gpt4Turbo: Self = "gpt-4-turbo"
  public static let gpt4_1_2025_04_14: Self = "gpt-4.1-2025-04-14"
  public static let gpt4_1Mini_2025_04_14: Self = "gpt-4.1-mini-2025-04-14"
  public static let gpt4_1Mini: Self = "gpt-4.1-mini"
  public static let gpt4_1Nano_2025_04_14: Self = "gpt-4.1-nano-2025-04-14"
  public static let gpt4_1Nano: Self = "gpt-4.1-nano"
  public static let gpt4_1: Self = "gpt-4.1"
  public static let gpt4: Self = "gpt-4"
  public static let gpt4o_2024_05_13: Self = "gpt-4o-2024-05-13"
  public static let gpt4o_2024_08_06: Self = "gpt-4o-2024-08-06"
  public static let gpt4o_2024_11_20: Self = "gpt-4o-2024-11-20"
  public static let gpt4oMini_2024_07_18: Self = "gpt-4o-mini-2024-07-18"
  public static let gpt4oMini: Self = "gpt-4o-mini"
  public static let gpt4o: Self = "gpt-4o"
  public static let gpt5_1: Self = "gpt-5.1"
  public static let gpt5_1ChatLatest: Self = "gpt-5.1-chat-latest"
  public static let gpt5_1CodexMini: Self = "gpt-5.1-codex-mini"
  public static let gpt5_1Codex: Self = "gpt-5.1-codex"
  public static let gpt5_1CodexMax: Self = "gpt-5.1-codex-max"
  public static let gpt5_2: Self = "gpt-5.2"
  public static let gpt5_2ChatLatest: Self = "gpt-5.2-chat-latest"
  public static let gpt5_2Pro: Self = "gpt-5.2-pro"
  public static let gpt5_2025_08_07: Self = "gpt-5-2025-08-07"
  public static let gpt5ChatLatest: Self = "gpt-5-chat-latest"
  public static let gpt5Codex: Self = "gpt-5-codex"
  public static let gpt5Mini_2025_08_07: Self = "gpt-5-mini-2025-08-07"
  public static let gpt5Mini: Self = "gpt-5-mini"
  public static let gpt5Nano_2025_08_07: Self = "gpt-5-nano-2025-08-07"
  public static let gpt5Nano: Self = "gpt-5-nano"
  public static let gpt5Pro_2025_10_06: Self = "gpt-5-pro-2025-10-06"
  public static let gpt5Pro: Self = "gpt-5-pro"
  public static let gpt5: Self = "gpt-5"
  public static let o1_2024_12_17: Self = "o1-2024-12-17"
  public static let o1: Self = "o1"
  public static let o3_2025_04_16: Self = "o3-2025-04-16"
  public static let o3Mini_2025_01_31: Self = "o3-mini-2025-01-31"
  public static let o3Mini: Self = "o3-mini"
  public static let o3: Self = "o3"
}

public struct OpenAICompletionModelID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }
}

public struct OpenAIEmbeddingModelID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }
}

public struct OpenAIImageModelID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }
}

public struct OpenAISpeechModelID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }
}

public struct OpenAITranscriptionModelID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }
}
