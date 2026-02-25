import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct AIKitMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    AIModelMacro.self,
    FieldMacro.self,
  ]
}

