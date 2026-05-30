import Foundation
import AIKit
import AIKitProviders

extension MCPClient {
  /// Fetches the server's tools and exposes each as a `DynamicToolSpec` whose `execute` calls back
  /// into this client. An MCP tool is, by construction, a dynamic tool: its schema is known only at
  /// runtime. Register the results into a `ToolRegistry` and pass it to `generateText`/`streamText`
  /// like any other tools.
  public func tools() async throws -> [String: DynamicToolSpec] {
    let definitions = try await listTools()
    var result: [String: DynamicToolSpec] = [:]
    for definition in definitions {
      let name = definition.name
      result[name] = dynamicTool(
        description: definition.description,
        inputSchema: definition.inputSchema,
        execute: { [self] input, _ in
          .final(try await self.callTool(name: name, arguments: input))
        }
      )
    }
    return result
  }

  /// Convenience: builds a fresh `ToolRegistry` populated with this server's tools.
  public func toolRegistry() async throws -> ToolRegistry {
    var registry = ToolRegistry()
    for (name, spec) in try await tools() {
      registry.register(name, spec)
    }
    return registry
  }
}
