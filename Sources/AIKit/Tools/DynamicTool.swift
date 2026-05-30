import Foundation
import AIKitProviders

/// A tool whose input/output schemas are not known at compile time.
///
/// Unlike `ToolSpec`, which is generic over `Codable` `Input`/`Output` types, a dynamic tool
/// works directly with `JSONValue` and carries a runtime `JSONSchema`. This is the shape used for
/// tools discovered at runtime — most importantly MCP server tools (see `AIKitMCP`).
///
/// Input is passed through untouched (no schema validation): dynamic tools trust the schema
/// advertised by their source, matching the upstream AI SDK `dynamicTool` semantics.
public struct DynamicToolSpec: Sendable {
  public var title: String?
  public var description: String?
  /// The runtime input schema advertised to the model.
  public var inputSchema: JSONSchema
  public var kind: ToolKind

  public var needsApproval: (@Sendable (_ input: JSONValue, _ context: ToolContext) async -> Bool)?

  public var onInputStart: (@Sendable (ToolContext) async -> Void)?
  public var onInputDelta: (@Sendable (_ delta: String, _ context: ToolContext) async -> Void)?
  public var onInputAvailable: (@Sendable (_ input: JSONValue, _ context: ToolContext) async -> Void)?

  public var execute: (@Sendable (_ input: JSONValue, _ context: ToolContext) async throws -> ToolExecution<JSONValue>)?

  public init(
    title: String? = nil,
    description: String? = nil,
    inputSchema: JSONSchema,
    kind: ToolKind = .client,
    needsApproval: (@Sendable (_ input: JSONValue, _ context: ToolContext) async -> Bool)? = nil,
    onInputStart: (@Sendable (ToolContext) async -> Void)? = nil,
    onInputDelta: (@Sendable (_ delta: String, _ context: ToolContext) async -> Void)? = nil,
    onInputAvailable: (@Sendable (_ input: JSONValue, _ context: ToolContext) async -> Void)? = nil,
    execute: (@Sendable (_ input: JSONValue, _ context: ToolContext) async throws -> ToolExecution<JSONValue>)? = nil
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

/// Creates a dynamic tool with a runtime schema. Mirrors the upstream AI SDK `dynamicTool()`.
public func dynamicTool(
  title: String? = nil,
  description: String? = nil,
  inputSchema: JSONSchema,
  kind: ToolKind = .client,
  needsApproval: (@Sendable (_ input: JSONValue, _ context: ToolContext) async -> Bool)? = nil,
  onInputStart: (@Sendable (ToolContext) async -> Void)? = nil,
  onInputDelta: (@Sendable (_ delta: String, _ context: ToolContext) async -> Void)? = nil,
  onInputAvailable: (@Sendable (_ input: JSONValue, _ context: ToolContext) async -> Void)? = nil,
  execute: (@Sendable (_ input: JSONValue, _ context: ToolContext) async throws -> ToolExecution<JSONValue>)? = nil
) -> DynamicToolSpec {
  DynamicToolSpec(
    title: title,
    description: description,
    inputSchema: inputSchema,
    kind: kind,
    needsApproval: needsApproval,
    onInputStart: onInputStart,
    onInputDelta: onInputDelta,
    onInputAvailable: onInputAvailable,
    execute: execute
  )
}

/// The dynamic counterpart to `AnyToolBox`. Because the tool loop drives every tool through the
/// JSON-shaped `AnyToolBoxProtocol`, a dynamic tool is simply a conformer whose input and output
/// are `JSONValue` — no changes to the loop are required.
internal struct DynamicToolBox: AnyToolBoxProtocol {
  let name: String
  let spec: DynamicToolSpec

  var isDynamic: Bool { true }

  var tool: AnyTool {
    AnyTool(
      name: name,
      title: spec.title,
      description: spec.description,
      inputSchema: spec.inputSchema
    )
  }

  var kind: ToolKind { spec.kind }

  func decodeInput(from value: JSONValue) throws -> AnySendable {
    // Passthrough: dynamic tools trust their advertised schema and do not validate input.
    AnySendable(value)
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
    guard let handler = spec.onInputAvailable, let json = input.value as? JSONValue else { return }
    await handler(json, context)
  }

  func needsApproval(_ input: AnySendable, context: ToolContext) async -> Bool? {
    guard let handler = spec.needsApproval, let json = input.value as? JSONValue else { return nil }
    return await handler(json, context)
  }

  func execute(_ input: AnySendable, context: ToolContext) async throws -> ToolExecution<AnySendable>? {
    guard let handler = spec.execute, let json = input.value as? JSONValue else { return nil }
    let result = try await handler(json, context)
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
    guard let json = output.value as? JSONValue else {
      throw AIKitError.invalidConfiguration("Dynamic tool output type mismatch for \(name).")
    }
    return json
  }
}
