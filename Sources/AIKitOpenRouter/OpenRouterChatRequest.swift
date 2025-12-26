import Foundation

struct OpenRouterCacheControl: Codable, Equatable, Sendable {
  var type: String
}

enum OpenRouterAudioFormat: String, Codable, CaseIterable, Sendable {
  case wav
  case mp3
  case aiff
  case aac
  case ogg
  case flac
  case m4a
  case pcm16
  case pcm24
}

enum OpenRouterChatMessageContent: Encodable, Equatable {
  case string(String)
  case parts([OpenRouterChatContentPart])

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .parts(let parts):
      try container.encode(parts)
    }
  }
}

struct OpenRouterChatMessage: Encodable, Equatable {
  var role: String
  var content: OpenRouterChatMessageContent?
  var toolCalls: [OpenRouterChatToolCall]?
  var toolCallID: String?
  var reasoning: String?
  var reasoningDetails: [ReasoningDetailUnion]?
  var annotations: [OpenRouterAnnotation]?
  var cacheControl: OpenRouterCacheControl?

  enum CodingKeys: String, CodingKey {
    case role
    case content
    case toolCalls = "tool_calls"
    case toolCallID = "tool_call_id"
    case reasoning
    case reasoningDetails = "reasoning_details"
    case annotations
    case cacheControl = "cache_control"
  }
}

enum OpenRouterChatContentPart: Encodable, Equatable {
  case text(String, cacheControl: OpenRouterCacheControl?)
  case imageURL(String, cacheControl: OpenRouterCacheControl?)
  case file(filename: String, fileData: String, cacheControl: OpenRouterCacheControl?)
  case inputAudio(data: String, format: OpenRouterAudioFormat, cacheControl: OpenRouterCacheControl?)

  enum CodingKeys: String, CodingKey {
    case type
    case text
    case imageURL = "image_url"
    case file
    case inputAudio = "input_audio"
    case cacheControl = "cache_control"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text, let cacheControl):
      try container.encode("text", forKey: .type)
      try container.encode(text, forKey: .text)
      try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
    case .imageURL(let url, let cacheControl):
      try container.encode("image_url", forKey: .type)
      try container.encode(OpenRouterImageURL(url: url), forKey: .imageURL)
      try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
    case .file(let filename, let fileData, let cacheControl):
      try container.encode("file", forKey: .type)
      try container.encode(OpenRouterFilePayload(filename: filename, fileData: fileData), forKey: .file)
      try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
    case .inputAudio(let data, let format, let cacheControl):
      try container.encode("input_audio", forKey: .type)
      try container.encode(OpenRouterInputAudio(data: data, format: format), forKey: .inputAudio)
      try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
    }
  }
}

struct OpenRouterImageURL: Codable, Equatable, Sendable {
  var url: String
}

struct OpenRouterFilePayload: Codable, Equatable, Sendable {
  var filename: String
  var fileData: String

  enum CodingKeys: String, CodingKey {
    case filename
    case fileData = "file_data"
  }
}

struct OpenRouterInputAudio: Codable, Equatable, Sendable {
  var data: String
  var format: OpenRouterAudioFormat
}

struct OpenRouterChatToolCall: Codable, Equatable, Sendable {
  var type: String
  var id: String
  var function: OpenRouterChatToolCallFunction
}

struct OpenRouterChatToolCallFunction: Codable, Equatable, Sendable {
  var name: String
  var arguments: String
}

