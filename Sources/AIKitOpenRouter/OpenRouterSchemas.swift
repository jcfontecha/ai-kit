import Foundation

enum ReasoningFormat: String, Codable, CaseIterable {
  case unknown = "unknown"
  case openAIResponsesV1 = "openai-responses-v1"
  case xAIResponsesV1 = "xai-responses-v1"
  case anthropicClaudeV1 = "anthropic-claude-v1"
  case googleGeminiV1 = "google-gemini-v1"
}

enum ReasoningDetailType: String, Codable {
  case summary = "reasoning.summary"
  case encrypted = "reasoning.encrypted"
  case text = "reasoning.text"
}

protocol ReasoningDetailCommonFields: Codable, Equatable {
  var id: String? { get set }
  var format: ReasoningFormat? { get set }
  var index: Int? { get set }
}

struct ReasoningDetailSummary: ReasoningDetailCommonFields {
  var type: ReasoningDetailType
  var summary: String
  var id: String?
  var format: ReasoningFormat?
  var index: Int?
}

struct ReasoningDetailEncrypted: ReasoningDetailCommonFields {
  var type: ReasoningDetailType
  var data: String
  var id: String?
  var format: ReasoningFormat?
  var index: Int?
}

struct ReasoningDetailText: ReasoningDetailCommonFields {
  var type: ReasoningDetailType
  var text: String?
  var signature: String?
  var id: String?
  var format: ReasoningFormat?
  var index: Int?
}

enum ReasoningDetailUnion: Codable, Equatable {
  case summary(ReasoningDetailSummary)
  case encrypted(ReasoningDetailEncrypted)
  case text(ReasoningDetailText)

  init(from decoder: Decoder) throws {
    if let summary = try? ReasoningDetailSummary(from: decoder) {
      self = .summary(summary)
      return
    }
    if let encrypted = try? ReasoningDetailEncrypted(from: decoder) {
      self = .encrypted(encrypted)
      return
    }
    if let text = try? ReasoningDetailText(from: decoder) {
      self = .text(text)
      return
    }
    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown reasoning detail"))
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .summary(let value):
      try value.encode(to: encoder)
    case .encrypted(let value):
      try value.encode(to: encoder)
    case .text(let value):
      try value.encode(to: encoder)
    }
  }

  var type: ReasoningDetailType {
    switch self {
    case .summary: return .summary
    case .encrypted: return .encrypted
    case .text: return .text
    }
  }
}

struct LossyDecodingArray<Element: Decodable>: Decodable {
  var elements: [Element]

  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var items: [Element] = []
    while container.isAtEnd == false {
      if let value = try? container.decode(Element.self) {
        items.append(value)
      } else {
        _ = try? container.decode(Discardable.self)
      }
    }
    self.elements = items
  }

  private struct Discardable: Decodable {}
}

struct OpenRouterImageResponse: Codable, Equatable {
  var type: String
  var imageURL: OpenRouterImageURL

  enum CodingKeys: String, CodingKey {
    case type
    case imageURL = "image_url"
  }
}

struct OpenRouterURLCitation: Codable, Equatable {
  var type: String
  var urlCitation: OpenRouterURLCitationPayload

  enum CodingKeys: String, CodingKey {
    case type
    case urlCitation = "url_citation"
  }
}

struct OpenRouterURLCitationPayload: Codable, Equatable {
  var endIndex: Int
  var startIndex: Int
  var title: String
  var url: String
  var content: String?

  enum CodingKeys: String, CodingKey {
    case endIndex = "end_index"
    case startIndex = "start_index"
    case title
    case url
    case content
  }
}

struct OpenRouterFileAnnotation: Codable, Equatable {
  var type: String
  var file: OpenRouterFileAnnotationFile
}

struct OpenRouterFileAnnotationFile: Codable, Equatable {
  var hash: String
  var name: String
  var content: [OpenRouterFileAnnotationContent]?
}

struct OpenRouterFileAnnotationContent: Codable, Equatable {
  var type: String
  var text: String?
}

struct OpenRouterLegacyFileAnnotation: Codable, Equatable {
  var type: String
  var fileAnnotation: OpenRouterLegacyFileAnnotationPayload

  enum CodingKeys: String, CodingKey {
    case type
    case fileAnnotation = "file_annotation"
  }
}

struct OpenRouterLegacyFileAnnotationPayload: Codable, Equatable {
  var fileID: String
  var quote: String?

  enum CodingKeys: String, CodingKey {
    case fileID = "file_id"
    case quote
  }
}

enum OpenRouterAnnotation: Codable, Equatable {
  case urlCitation(OpenRouterURLCitation)
  case file(OpenRouterFileAnnotation)
  case fileAnnotation(OpenRouterLegacyFileAnnotation)

  init(from decoder: Decoder) throws {
    if let citation = try? OpenRouterURLCitation(from: decoder) {
      self = .urlCitation(citation)
      return
    }
    if let file = try? OpenRouterFileAnnotation(from: decoder) {
      self = .file(file)
      return
    }
    if let fileAnnotation = try? OpenRouterLegacyFileAnnotation(from: decoder) {
      self = .fileAnnotation(fileAnnotation)
      return
    }
    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown annotation"))
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .urlCitation(let value):
      try value.encode(to: encoder)
    case .file(let value):
      try value.encode(to: encoder)
    case .fileAnnotation(let value):
      try value.encode(to: encoder)
    }
  }
}
