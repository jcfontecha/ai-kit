import Foundation
import AIKitProviders

public struct OutputContext: Sendable {
  public var finishReason: FinishReason
  public var usage: Usage
  public var providerMetadata: ProviderMetadata?
  public var response: LanguageModelResponseMetadata?

  public init(
    finishReason: FinishReason,
    usage: Usage,
    providerMetadata: ProviderMetadata? = nil,
    response: LanguageModelResponseMetadata? = nil
  ) {
    self.finishReason = finishReason
    self.usage = usage
    self.providerMetadata = providerMetadata
    self.response = response
  }
}

public protocol OutputSpec: Sendable {
  associatedtype Complete: Sendable
  associatedtype Partial: Sendable

  var responseFormat: ResponseFormat { get }

  func parseComplete(text: String, context: OutputContext) async throws -> Complete
  func parsePartial(text: String) async -> Partial?
}

public enum Output {
  // NOTE: These are interface types only; parsing is intentionally not implemented yet.

  public struct Text: OutputSpec {
    public init() {}
    public var responseFormat: ResponseFormat { .text }
    public func parseComplete(text: String, context: OutputContext) async throws -> String {
      text
    }
    public func parsePartial(text: String) async -> String? { text }
  }

  public struct JSON: OutputSpec {
    public init(name: String? = nil, description: String? = nil) {
      self.name = name
      self.description = description
    }

    public var name: String?
    public var description: String?

    public var responseFormat: ResponseFormat {
      .json(name: name, description: description)
    }

    public func parseComplete(text: String, context: OutputContext) async throws -> JSONValue {
      do {
        return try OutputParsing.parseJSONValue(text)
      } catch {
        throw NoObjectGeneratedError(
          message: "No object generated: could not parse the response.",
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      }
    }

    public func parsePartial(text: String) async -> JSONValue? {
      OutputParsing.parsePartialJSONValue(text)
    }
  }

  public struct Object<T: Codable & Sendable>: OutputSpec {
    public init(schema: ObjectSchema<T>, name: String? = nil, description: String? = nil) {
      self.schema = schema
      self.name = name
      self.description = description
    }

    public var schema: ObjectSchema<T>
    public var name: String?
    public var description: String?

    public var responseFormat: ResponseFormat {
      .jsonSchema(
        schema: schema.jsonSchema,
        name: name ?? schema.name,
        description: description ?? schema.description
      )
    }

    public func parseComplete(text: String, context: OutputContext) async throws -> T {
      do {
        let json = try OutputParsing.parseJSONValue(text)
        return try OutputParsing.decodeJSONValue(json, as: T.self)
      } catch let error as OutputParsing.ParseFailure {
        throw NoObjectGeneratedError(
          message: error.message,
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      } catch {
        throw NoObjectGeneratedError(
          message: "No object generated: response did not match schema.",
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      }
    }

    public func parsePartial(text: String) async -> JSONValue? {
      guard let value = OutputParsing.parsePartialJSONValue(text) else { return nil }
      if case .object = value { return value }
      return nil
    }
  }

  public struct Array<Element: Codable & Sendable>: OutputSpec {
    public init(elementSchema: ObjectSchema<Element>, name: String? = nil, description: String? = nil) {
      self.elementSchema = elementSchema
      self.name = name
      self.description = description
    }

    public var elementSchema: ObjectSchema<Element>
    public var name: String?
    public var description: String?

    public var responseFormat: ResponseFormat {
      // Matches the JS SDK pattern of wrapping elements in an object payload:
      // { "elements": [ ... ] }
      var itemSchemaValue = elementSchema.jsonSchema.value
      itemSchemaValue.removeValue(forKey: "$schema")

      return .jsonSchema(
        schema: .object(
          properties: [
            "elements": .init([
              "type": .string("array"),
              "items": .object(itemSchemaValue),
            ]),
          ],
          required: ["elements"],
          additionalProperties: false,
          description: description
        ),
        name: name,
        description: description
      )
    }

    public func parseComplete(text: String, context: OutputContext) async throws -> [Element] {
      do {
        let json = try OutputParsing.parseJSONValue(text)
        guard case let .object(obj) = json,
              case let .array(elements) = obj["elements"] else {
          throw OutputParsing.ParseFailure.schemaMismatch
        }
        return try elements.map { try OutputParsing.decodeJSONValue($0, as: Element.self) }
      } catch let error as OutputParsing.ParseFailure {
        throw NoObjectGeneratedError(
          message: error.message,
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      } catch {
        throw NoObjectGeneratedError(
          message: "No object generated: response did not match schema.",
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      }
    }

    public func parsePartial(text: String) async -> [Element]? {
      return OutputParsing.parsePartialElements(text: text, elementType: Element.self)
    }
  }

  public struct Choice: OutputSpec {
    public init(options: [String], name: String? = nil, description: String? = nil) {
      self.options = options
      self.name = name
      self.description = description
    }

    public var options: [String]
    public var name: String?
    public var description: String?

    public var responseFormat: ResponseFormat {
      // Matches the JS SDK pattern of wrapping the choice in an object payload:
      // { "result": "..." }
      .jsonSchema(
        schema: .object(
          properties: [
            "result": .init([
              "type": .string("string"),
              "enum": .array(options.map(JSONValue.string)),
            ]),
          ],
          required: ["result"],
          additionalProperties: false,
          description: description
        ),
        name: name,
        description: description
      )
    }

    public func parseComplete(text: String, context: OutputContext) async throws -> String {
      do {
        let json = try OutputParsing.parseJSONValue(text)
        guard case let .object(obj) = json,
              case let .string(result) = obj["result"],
              options.contains(result) else {
          throw OutputParsing.ParseFailure.schemaMismatch
        }
        return result
      } catch let error as OutputParsing.ParseFailure {
        throw NoObjectGeneratedError(
          message: error.message,
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      } catch {
        throw NoObjectGeneratedError(
          message: "No object generated: response did not match schema.",
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      }
    }

    public func parsePartial(text: String) async -> String? {
      guard let partial = OutputParsing.parsePartialChoice(text: text, key: "result") else {
        return nil
      }
      if options.contains(partial) { return partial }
      let matches = options.filter { $0.hasPrefix(partial) }
      if matches.count == 1 { return matches[0] }
      return nil
    }
  }

  public struct TypedObject<T: SchemaProviding>: OutputSpec {
    public init(schema: ObjectSchema<T> = T.schema, name: String? = nil, description: String? = nil) {
      self.schema = schema
      self.name = name
      self.description = description
    }

    public var schema: ObjectSchema<T>
    public var name: String?
    public var description: String?

    public var responseFormat: ResponseFormat {
      .jsonSchema(
        schema: schema.jsonSchema,
        name: name ?? schema.name,
        description: description ?? schema.description
      )
    }

    public func parseComplete(text: String, context: OutputContext) async throws -> T {
      do {
        let json = try OutputParsing.parseJSONValue(text)
        return try OutputParsing.decodeJSONValue(json, as: T.self)
      } catch let error as OutputParsing.ParseFailure {
        throw NoObjectGeneratedError(
          message: error.message,
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      } catch {
        throw NoObjectGeneratedError(
          message: "No object generated: response did not match schema.",
          finishReason: context.finishReason,
          usage: context.usage,
          response: context.response
        )
      }
    }

    public func parsePartial(text: String) async -> T.Partial? {
      guard let value = OutputParsing.parsePartialJSONValue(text) else { return nil }
      do {
        return try OutputParsing.decodeJSONValue(value, as: T.Partial.self)
      } catch {
        return nil
      }
    }
  }
}

public extension Output {
  static func text() -> Text { .init() }
  static func json(name: String? = nil, description: String? = nil) -> JSON { .init(name: name, description: description) }
  static func object<T: Codable & Sendable>(
    _ type: T.Type,
    schema: ObjectSchema<T>,
    name: String? = nil,
    description: String? = nil
  ) -> Object<T> {
    .init(schema: schema, name: name, description: description)
  }
  static func typedObject<T: SchemaProviding>(
    _ type: T.Type,
    name: String? = nil,
    description: String? = nil
  ) -> TypedObject<T> {
    .init(schema: T.schema, name: name, description: description)
  }
  static func array<E: Codable & Sendable>(
    _ element: E.Type,
    elementSchema: ObjectSchema<E>,
    name: String? = nil,
    description: String? = nil
  ) -> Array<E> {
    .init(elementSchema: elementSchema, name: name, description: description)
  }
  static func choice(options: [String], name: String? = nil, description: String? = nil) -> Choice {
    .init(options: options, name: name, description: description)
  }
}
