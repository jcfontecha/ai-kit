import Foundation

enum OpenAIAudioFormat: String, Codable, CaseIterable, Sendable {
  case wav
  case mp3
}

enum OpenAIChatMessageContent: Encodable, Equatable {
  case string(String)
  case parts([OpenAIChatContentPart])

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

struct OpenAIChatMessage: Encodable, Equatable {
  var role: String
  var content: OpenAIChatMessageContent?
  var toolCalls: [OpenAIChatToolCall]?
  var toolCallID: String?

  enum CodingKeys: String, CodingKey {
    case role
    case content
    case toolCalls = "tool_calls"
    case toolCallID = "tool_call_id"
  }
}

enum OpenAIChatContentPart: Encodable, Equatable {
  case text(String)
  case imageURL(String)
  case file(filename: String, fileData: String)
  case inputAudio(data: String, format: OpenAIAudioFormat)

  enum CodingKeys: String, CodingKey {
    case type
    case text
    case imageURL = "image_url"
    case file
    case inputAudio = "input_audio"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode("text", forKey: .type)
      try container.encode(text, forKey: .text)
    case .imageURL(let url):
      try container.encode("image_url", forKey: .type)
      try container.encode(OpenAIImageURL(url: url), forKey: .imageURL)
    case .file(let filename, let fileData):
      try container.encode("file", forKey: .type)
      try container.encode(OpenAIFilePayload(filename: filename, fileData: fileData), forKey: .file)
    case .inputAudio(let data, let format):
      try container.encode("input_audio", forKey: .type)
      try container.encode(OpenAIInputAudio(data: data, format: format), forKey: .inputAudio)
    }
  }
}

struct OpenAIImageURL: Codable, Equatable, Sendable {
  var url: String
}

struct OpenAIFilePayload: Codable, Equatable, Sendable {
  var filename: String
  var fileData: String

  enum CodingKeys: String, CodingKey {
    case filename
    case fileData = "file_data"
  }
}

struct OpenAIInputAudio: Codable, Equatable, Sendable {
  var data: String
  var format: OpenAIAudioFormat
}

struct OpenAIChatToolCall: Codable, Equatable, Sendable {
  var type: String
  var id: String
  var function: OpenAIChatToolCallFunction
}

struct OpenAIChatToolCallFunction: Codable, Equatable, Sendable {
  var name: String
  var arguments: String
}
