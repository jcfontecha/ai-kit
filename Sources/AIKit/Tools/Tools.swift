import Foundation
import AIKitProviders

public struct AnySendable: @unchecked Sendable {
  public let value: Any
  public init(_ value: Any) { self.value = value }
}

public struct ToolID<Input: Sendable, Output: Sendable>: Hashable, Sendable {
  public var name: String
  public init(_ name: String) { self.name = name }
}

public struct ToolContext: Sendable {
  public var toolCallID: String
  public var messages: [ModelMessage]
  public var experimentalContext: AnySendable?

  public init(toolCallID: String, messages: [ModelMessage], experimentalContext: AnySendable? = nil) {
    self.toolCallID = toolCallID
    self.messages = messages
    self.experimentalContext = experimentalContext
  }
}

public enum ToolKind: Sendable, Equatable {
  case client
  case provider(supportsDeferredResults: Bool)
}

public typealias ToolNeedsApproval<Input> = @Sendable (_ input: Input, _ context: ToolContext) async -> Bool

public enum ToolProgress<Output: Sendable>: Sendable {
  case preliminary(Output)
  case final(Output)
}

public enum ToolExecution<Output: Sendable>: Sendable {
  case final(Output)
  case streaming(AsyncThrowingStream<ToolProgress<Output>, Error>)
}

public struct ToolSpec<Input: Codable & Sendable, Output: Codable & Sendable>: Sendable {
  public var title: String?
  public var description: String?
  /// The single source of truth for tool input schema.
  public var inputSchema: ObjectSchema<Input>
  public var kind: ToolKind

  public var needsApproval: ToolNeedsApproval<Input>?

  public var onInputStart: (@Sendable (ToolContext) async -> Void)?
  public var onInputDelta: (@Sendable (_ delta: String, _ context: ToolContext) async -> Void)?
  public var onInputAvailable: (@Sendable (_ input: Input, _ context: ToolContext) async -> Void)?

  public var execute: (@Sendable (_ input: Input, _ context: ToolContext) async throws -> ToolExecution<Output>)?

  public init(
    title: String? = nil,
    description: String? = nil,
    inputSchema: ObjectSchema<Input>,
    kind: ToolKind = .client,
    needsApproval: ToolNeedsApproval<Input>? = nil,
    onInputStart: (@Sendable (ToolContext) async -> Void)? = nil,
    onInputDelta: (@Sendable (_ delta: String, _ context: ToolContext) async -> Void)? = nil,
    onInputAvailable: (@Sendable (_ input: Input, _ context: ToolContext) async -> Void)? = nil,
    execute: (@Sendable (_ input: Input, _ context: ToolContext) async throws -> ToolExecution<Output>)? = nil
  ) {
    self.title = title
    self.description = description
    self.inputSchema = inputSchema
    self.kind = kind
    self.needsApproval = needsApproval
    self.onInputStart = onInputStart
    self.onInputDelta = onInputDelta
    self.onInputAvailable = onInputAvailable
    self.execute = execute
  }
}

internal struct AnyTool: Sendable {
  public var name: String
  public var title: String?
  public var description: String?
  public var inputSchema: JSONSchema

  public init(name: String, title: String? = nil, description: String? = nil, inputSchema: JSONSchema) {
    self.name = name
    self.title = title
    self.description = description
    self.inputSchema = inputSchema
  }

  public var definition: ToolDefinition {
    .init(name: name, description: description, inputSchema: inputSchema)
  }
}

internal protocol AnyToolBoxProtocol: Sendable {
  var tool: AnyTool { get }
  var kind: ToolKind { get }
  /// Whether this tool carries a runtime (vs. compile-time) schema. Used to tag emitted
  /// tool calls/results as `dynamic`. Statically-typed tools default to `false`.
  var isDynamic: Bool { get }
  func decodeInput(from value: JSONValue) throws -> AnySendable
  func onInputStart(context: ToolContext) async
  func onInputDelta(_ delta: String, context: ToolContext) async
  func onInputAvailable(_ input: AnySendable, context: ToolContext) async
  func needsApproval(_ input: AnySendable, context: ToolContext) async -> Bool?
  func execute(_ input: AnySendable, context: ToolContext) async throws -> ToolExecution<AnySendable>?
  func encodeOutput(_ output: AnySendable) throws -> JSONValue
}

extension AnyToolBoxProtocol {
  var isDynamic: Bool { false }
}

internal struct AnyToolBox<Input: Codable & Sendable, Output: Codable & Sendable>: AnyToolBoxProtocol {
  let id: ToolID<Input, Output>
  let spec: ToolSpec<Input, Output>

  var tool: AnyTool {
    AnyTool(
      name: id.name,
      title: spec.title,
      description: spec.description,
      inputSchema: spec.inputSchema.jsonSchema
    )
  }

  var kind: ToolKind {
    spec.kind
  }

  func decodeInput(from value: JSONValue) throws -> AnySendable {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Input.self, from: data)
    return AnySendable(decoded)
  }

  func onInputStart(context: ToolContext) async {
    guard let handler = spec.onInputStart else { return }
    await handler(context)
  }

  func onInputDelta(_ delta: String, context: ToolContext) async {
    guard let handler = spec.onInputDelta else { return }
    await handler(delta, context)
  }

  func onInputAvailable(_ input: AnySendable, context: ToolContext) async {
    guard let handler = spec.onInputAvailable, let typed = input.value as? Input else { return }
    await handler(typed, context)
  }

  func needsApproval(_ input: AnySendable, context: ToolContext) async -> Bool? {
    guard let handler = spec.needsApproval, let typed = input.value as? Input else { return nil }
    return await handler(typed, context)
  }

  func execute(_ input: AnySendable, context: ToolContext) async throws -> ToolExecution<AnySendable>? {
    guard let handler = spec.execute, let typed = input.value as? Input else { return nil }
    let result = try await handler(typed, context)
    switch result {
    case .final(let output):
      return .final(AnySendable(output))
    case .streaming(let stream):
      let mapped = AsyncThrowingStream<ToolProgress<AnySendable>, Error> { continuation in
        Task {
          do {
            for try await progress in stream {
              switch progress {
              case .preliminary(let value):
                continuation.yield(.preliminary(AnySendable(value)))
              case .final(let value):
                continuation.yield(.final(AnySendable(value)))
              }
            }
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
      }
      return .streaming(mapped)
    }
  }

  func encodeOutput(_ output: AnySendable) throws -> JSONValue {
    guard let typed = output.value as? Output else {
      throw AIKitError.invalidConfiguration("Tool output type mismatch for \(id.name).")
    }
    let data = try JSONEncoder().encode(typed)
    let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    if let value = JSONValue.from(json) {
      return value
    }
    return .null
  }
}

public struct ToolRegistry: Sendable {
  private var toolBoxesByName: [String: any AnyToolBoxProtocol]

  public init() {
    self.toolBoxesByName = [:]
  }

  public mutating func register<I: Codable & Sendable, O: Codable & Sendable>(
    _ id: ToolID<I, O>,
    _ tool: ToolSpec<I, O>
  ) {
    toolBoxesByName[id.name] = AnyToolBox(id: id, spec: tool)
  }

  /// Registers a dynamic (runtime-schema) tool under the given name.
  public mutating func register(_ name: String, _ tool: DynamicToolSpec) {
    toolBoxesByName[name] = DynamicToolBox(name: name, spec: tool)
  }

  public var definitions: [ToolDefinition] {
    toolBoxesByName.values.map { $0.tool.definition }.sorted { $0.name < $1.name }
  }

  internal func toolBox(named name: String) -> (any AnyToolBoxProtocol)? {
    toolBoxesByName[name]
  }

  internal func toolKind(named name: String) -> ToolKind? {
    toolBoxesByName[name]?.kind
  }

  internal var allToolNames: [String] {
    toolBoxesByName.keys.sorted()
  }

  internal var isEmpty: Bool {
    toolBoxesByName.isEmpty
  }
}
