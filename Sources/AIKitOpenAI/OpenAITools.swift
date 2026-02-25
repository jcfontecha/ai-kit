import Foundation

public struct OpenAIToolDefinition: Sendable, Equatable {
  public var name: String
  public var description: String?

  public init(name: String, description: String? = nil) {
    self.name = name
    self.description = description
  }
}

public struct OpenAITools: Sendable {
  public init() {}

  public var applyPatch: OpenAIToolDefinition {
    .init(name: "apply_patch")
  }

  public var codeInterpreter: OpenAIToolDefinition {
    .init(name: "code_interpreter")
  }

  public var fileSearch: OpenAIToolDefinition {
    .init(name: "file_search")
  }

  public var imageGeneration: OpenAIToolDefinition {
    .init(name: "image_generation")
  }

  public var localShell: OpenAIToolDefinition {
    .init(name: "local_shell")
  }

  public var shell: OpenAIToolDefinition {
    .init(name: "shell")
  }

  public var webSearchPreview: OpenAIToolDefinition {
    .init(name: "web_search_preview")
  }

  public var webSearch: OpenAIToolDefinition {
    .init(name: "web_search")
  }

  public var mcp: OpenAIToolDefinition {
    .init(name: "mcp")
  }
}
