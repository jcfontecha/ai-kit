import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct AIModelMacro: ExtensionMacro, MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    [try ExtensionDeclSyntax("extension \(type.trimmed): SchemaProviding {}")]
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let typeName = extractTypeName(from: declaration)
    let properties: [PropertyInfo]

    if let structDecl = declaration.as(StructDeclSyntax.self) {
      properties = try extractProperties(from: structDecl)
    } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
      properties = try extractProperties(from: classDecl)
    } else {
      throw AIModelMacroError.notAStructOrClass
    }

    let schemaDecl = try generateSchemaProperty(typeName: typeName, properties: properties)
    let partialDecl = try generatePartialType(properties: properties)

    return [DeclSyntax(schemaDecl), DeclSyntax(partialDecl)]
  }

  private static func extractTypeName(from declaration: some DeclGroupSyntax) -> String {
    if let structDecl = declaration.as(StructDeclSyntax.self) { return structDecl.name.text }
    if let classDecl = declaration.as(ClassDeclSyntax.self) { return classDecl.name.text }
    return "UnknownType"
  }

  private static func extractProperties(from decl: some DeclGroupSyntax) throws -> [PropertyInfo] {
    var properties: [PropertyInfo] = []

    for member in decl.memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }

      // Skip static properties and computed properties.
      guard
        !variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }),
        let binding = variable.bindings.first,
        binding.accessorBlock == nil
      else { continue }

      guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
      let name = pattern.identifier.text

      guard let typeAnnotation = binding.typeAnnotation else {
        throw AIModelMacroError.missingTypeAnnotation(property: name)
      }

      let rawType = typeAnnotation.type.trimmedDescription
      let metadata = extractFieldMetadata(from: variable.attributes)

      properties.append(.init(
        name: name,
        type: rawType,
        fieldMetadata: metadata,
        isOptional: isOptionalType(rawType)
      ))
    }

    return properties
  }

  private static func extractFieldMetadata(from attributes: AttributeListSyntax) -> FieldMetadata? {
    for attr in attributes {
      guard let attribute = attr.as(AttributeSyntax.self) else { continue }
      guard attribute.attributeName.trimmedDescription == "Field" else { continue }

      var meta = FieldMetadata()

      guard case let .argumentList(args) = attribute.arguments else { return meta }

      for arg in args {
        if let label = arg.label?.text {
          switch label {
          case "minLength":
            meta.minLength = arg.expression.trimmedDescription.intValue
          case "maxLength":
            meta.maxLength = arg.expression.trimmedDescription.intValue
          case "pattern":
            meta.pattern = arg.expression.trimmedDescription.stringLiteralValue
          case "format":
            meta.format = arg.expression.trimmedDescription.stringLiteralValue
          case "range":
            let text = arg.expression.trimmedDescription
            if let (min, max) = parseClosedRangeDoubles(text) {
              meta.minimum = min
              meta.maximum = max
            }
          case "enum":
            meta.enumValues = parseStringArrayLiteral(arg.expression.trimmedDescription)
          case "minItems":
            meta.minItems = arg.expression.trimmedDescription.intValue
          case "maxItems":
            meta.maxItems = arg.expression.trimmedDescription.intValue
          default:
            break
          }
        } else {
          if meta.description == nil {
            meta.description = arg.expression.trimmedDescription.stringLiteralValue
          }
        }
      }

      return meta
    }

    return nil
  }

  private static func generateSchemaProperty(typeName: String, properties: [PropertyInfo]) throws -> VariableDeclSyntax {
    let requiredKeys = properties.filter { !$0.isOptional }.map { "\"\($0.name)\"" }.joined(separator: ", ")
    let propsLines = properties.map { property in
      "      \"\(property.name)\": \(jsonSchemaExpr(for: property))"
    }.joined(separator: ",\n")

    return try VariableDeclSyntax(
      """
      public static var schema: ObjectSchema<\(raw: typeName)> {
        .manual(
          jsonSchema: .object(
            properties: [
      \(raw: propsLines)
            ],
            required: [\(raw: requiredKeys)],
            additionalProperties: false
          ),
          name: "\(raw: typeName)"
        )
      }
      """
    )
  }

  private static func jsonSchemaExpr(for property: PropertyInfo) -> String {
    let baseType = stripOptional(from: property.type)
    let descriptionArg: String? = property.fieldMetadata?.description.map { "description: \"\(escapeString($0))\"" }

    switch baseType {
    case "String":
      var args: [String] = []
      if let descriptionArg { args.append(descriptionArg) }
      if let minLength = property.fieldMetadata?.minLength { args.append("minLength: \(minLength)") }
      if let maxLength = property.fieldMetadata?.maxLength { args.append("maxLength: \(maxLength)") }
      if let pattern = property.fieldMetadata?.pattern { args.append("pattern: \"\(escapeString(pattern))\"") }
      if let format = property.fieldMetadata?.format { args.append("format: \"\(escapeString(format))\"") }
      if let enums = property.fieldMetadata?.enumValues {
        let list = enums.map { "\"\(escapeString($0))\"" }.joined(separator: ", ")
        args.append("enum: [\(list)]")
      }
      return ".string(\(args.joined(separator: ", ")))"

    case "Int":
      var args: [String] = []
      if let descriptionArg { args.append(descriptionArg) }
      if let min = property.fieldMetadata?.minimum { args.append("minimum: \(Int(min))") }
      if let max = property.fieldMetadata?.maximum { args.append("maximum: \(Int(max))") }
      return ".integer(\(args.joined(separator: ", ")))"

    case "Double", "Float":
      var args: [String] = []
      if let descriptionArg { args.append(descriptionArg) }
      if let min = property.fieldMetadata?.minimum { args.append("minimum: \(min)") }
      if let max = property.fieldMetadata?.maximum { args.append("maximum: \(max)") }
      return ".number(\(args.joined(separator: ", ")))"

    case "Bool":
      var args: [String] = []
      if let descriptionArg { args.append(descriptionArg) }
      return ".boolean(\(args.joined(separator: ", ")))"

    case "Date":
      var args: [String] = []
      if let descriptionArg { args.append(descriptionArg) }
      args.append("format: \"date-time\"")
      return ".string(\(args.joined(separator: ", ")))"

    case "URL":
      var args: [String] = []
      if let descriptionArg { args.append(descriptionArg) }
      args.append("format: \"uri\"")
      return ".string(\(args.joined(separator: ", ")))"

    case "UUID":
      var args: [String] = []
      if let descriptionArg { args.append(descriptionArg) }
      args.append("format: \"uuid\"")
      return ".string(\(args.joined(separator: ", ")))"

    default:
      if let arrayElement = parseArrayElementType(baseType) {
        let elementSchema = schemaExprForArrayElement(arrayElement)
        var arrArgs: [String] = ["items: \(elementSchema)"]
        if let descriptionArg { arrArgs.append(descriptionArg) }
        if let minItems = property.fieldMetadata?.minItems { arrArgs.append("minItems: \(minItems)") }
        if let maxItems = property.fieldMetadata?.maxItems { arrArgs.append("maxItems: \(maxItems)") }
        return ".array(\(arrArgs.joined(separator: ", ")))"
      }

      // Nested object schema: assume SchemaProviding.
      let nested = "\(baseType).schema.jsonSchema"
      if let descriptionArg {
        return "\(nested).withDescription(\(descriptionArg.replacingOccurrences(of: "description: ", with: "")))"
      }
      return nested
    }
  }

  private static func generatePartialType(properties: [PropertyInfo]) throws -> StructDeclSyntax {
    let members = properties.map { property in
      let optionalType = makeOptional(property.type)
      return "  public var \(property.name): \(optionalType)"
    }

    return try StructDeclSyntax(
      """
      public struct Partial: Codable, Sendable {
      \(raw: members.joined(separator: "\n"))

        public init(\(raw: properties.map { "\($0.name): \(makeOptional($0.type)) = nil" }.joined(separator: ", "))) {
      \(raw: properties.map { "    self.\($0.name) = \($0.name)" }.joined(separator: "\n"))
        }
      }
      """
    )
  }
}

public struct FieldMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // @Field is metadata only.
    []
  }
}

private struct PropertyInfo {
  let name: String
  let type: String
  let fieldMetadata: FieldMetadata?
  let isOptional: Bool
}

private struct FieldMetadata {
  var description: String?
  var minimum: Double?
  var maximum: Double?
  var minLength: Int?
  var maxLength: Int?
  var pattern: String?
  var format: String?
  var enumValues: [String]?
  var minItems: Int?
  var maxItems: Int?
}

private enum AIModelMacroError: Error, CustomStringConvertible {
  case notAStructOrClass
  case missingTypeAnnotation(property: String)

  var description: String {
    switch self {
    case .notAStructOrClass:
      "@AIModel can only be applied to structs or classes"
    case .missingTypeAnnotation(let property):
      "Property '\(property)' must have an explicit type annotation"
    }
  }
}

private func isOptionalType(_ type: String) -> Bool {
  type.hasSuffix("?") || (type.hasPrefix("Optional<") && type.hasSuffix(">"))
}

private func stripOptional(from type: String) -> String {
  if type.hasSuffix("?") { return String(type.dropLast()) }
  if type.hasPrefix("Optional<"), type.hasSuffix(">") {
    return String(type.dropFirst("Optional<".count).dropLast())
  }
  return type
}

private func makeOptional(_ type: String) -> String {
  let t = type.trimmingCharacters(in: .whitespacesAndNewlines)
  return isOptionalType(t) ? t : "\(t)?"
}

private func parseArrayElementType(_ type: String) -> String? {
  // Support `[T]` spelling.
  if type.hasPrefix("["), type.hasSuffix("]") {
    return String(type.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  // Support `Array<T>` spelling.
  if type.hasPrefix("Array<"), type.hasSuffix(">") {
    return String(type.dropFirst("Array<".count).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return nil
}

private func schemaExprForArrayElement(_ elementType: String) -> String {
  switch elementType {
  case "String": return ".string()"
  case "Int": return ".integer()"
  case "Double", "Float": return ".number()"
  case "Bool": return ".boolean()"
  case "Date": return ".string(format: \"date-time\")"
  case "URL": return ".string(format: \"uri\")"
  case "UUID": return ".string(format: \"uuid\")"
  default:
    // Nested schema: drop $schema when used as items.
    return "\(elementType).schema.jsonSchema.withoutSchemaURI()"
  }
}

private func escapeString(_ s: String) -> String {
  s
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")
}

private func parseClosedRangeDoubles(_ text: String) -> (Double, Double)? {
  guard let rangeIdx = text.range(of: "...") else { return nil }
  let left = String(text[..<rangeIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
  let right = String(text[rangeIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  guard let a = Double(left), let b = Double(right) else { return nil }
  return (a, b)
}

private func parseStringArrayLiteral(_ text: String) -> [String]? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
  let inner = trimmed.dropFirst().dropLast()
  if String(inner).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }

  return inner
    .split(separator: ",")
    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    .compactMap { token in
      token.stringLiteralValue
    }
}

private extension String {
  var stringLiteralValue: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else { return nil }
    return String(trimmed.dropFirst().dropLast())
  }

  var intValue: Int? {
    Int(trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

