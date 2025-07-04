import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// The @AIModel macro that generates SchemaProviding conformance and schema property
public struct AIModelMacro: ExtensionMacro, MemberMacro {
    
    // MARK: - ExtensionMacro Implementation
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Generate extension with SchemaProviding conformance
        let extensionDecl = try ExtensionDeclSyntax(
            "extension \(type.trimmed): SchemaProviding {}"
        )
        return [extensionDecl]
    }
    
    // MARK: - MemberMacro Implementation
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract struct/class declaration
        guard let structDecl = declaration.as(StructDeclSyntax.self) ?? 
              declaration.as(ClassDeclSyntax.self)?.asProtocol(DeclGroupSyntax.self) else {
            throw AIModelMacroError.notAStructOrClass
        }
        
        // Extract type name
        let typeName = extractTypeName(from: declaration)
        
        // Extract properties with @Field annotations
        let properties = try extractProperties(from: structDecl)
        
        // Generate schema property
        let schemaDecl = try generateSchemaProperty(
            typeName: typeName,
            properties: properties
        )
        
        // Generate Partial nested type for streaming support
        let partialTypeDecl = try generatePartialType(
            typeName: typeName,
            properties: properties
        )
        
        return [
            DeclSyntax(schemaDecl),
            DeclSyntax(partialTypeDecl)
        ]
    }
    
    // MARK: - Helper Methods
    
    private static func extractTypeName(from declaration: some DeclGroupSyntax) -> String {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.name.text
        } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        }
        return "UnknownType"
    }
    
    private static func extractProperties(from declaration: some DeclGroupSyntax) throws -> [PropertyInfo] {
        var properties: [PropertyInfo] = []
        
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            
            // Skip static and computed properties
            guard variable.bindingSpecifier.tokenKind == .keyword(.let) ||
                  variable.bindingSpecifier.tokenKind == .keyword(.var),
                  !variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }),
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil else { continue }
            
            // Extract property name
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let propertyName = pattern.identifier.text
            
            // Extract type
            guard let typeAnnotation = binding.typeAnnotation else {
                throw AIModelMacroError.missingTypeAnnotation(property: propertyName)
            }
            let propertyType = typeAnnotation.type.trimmedDescription
            
            // Extract field metadata from @Field attributes
            let fieldMetadata = extractFieldMetadata(from: variable.attributes)
            
            properties.append(PropertyInfo(
                name: propertyName,
                type: propertyType,
                fieldMetadata: fieldMetadata,
                isOptional: isOptionalType(propertyType)
            ))
        }
        
        return properties
    }
    
    
    private static func extractFieldMetadata(from attributes: AttributeListSyntax) -> FieldMetadata? {
        for attribute in attributes {
            guard let attributeSyntax = attribute.as(AttributeSyntax.self),
                  attributeSyntax.attributeName.trimmedDescription == "Field" else { continue }
            
            // Parse Field arguments
            var description: String?
            var minValue: String?
            var maxValue: String?
            var minLength: Int?
            var maxLength: Int?
            var pattern: String?
            var format: String?
            var enumValues: [String]?
            var maxItems: Int?
            
            if let arguments = attributeSyntax.arguments?.as(LabeledExprListSyntax.self) {
                for argument in arguments {
                    let label = argument.label?.text ?? ""
                    
                    switch label {
                    case "", "_": // Unlabeled parameter is description
                        if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            description = segment.content.text
                        }
                    case "range":
                        // Handle range expressions like 1...10 or 0.01...99999.99
                        if let rangeExpr = argument.expression.as(SequenceExprSyntax.self) {
                            let elements = rangeExpr.elements.map { $0 }
                            if elements.count >= 3 {
                                // First element is the min value
                                minValue = elements[0].trimmedDescription
                                // Last element is the max value
                                maxValue = elements[elements.count - 1].trimmedDescription
                            }
                        } else {
                            // Handle other range formats
                            let rangeString = argument.expression.trimmedDescription
                            if rangeString.contains("...") {
                                let parts = rangeString.split(separator: ".")
                                    .filter { !$0.isEmpty }
                                if parts.count >= 2 {
                                    minValue = String(parts[0])
                                    maxValue = String(parts[parts.count - 1])
                                }
                            }
                        }
                    case "minLength":
                        if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                            minLength = Int(intLiteral.literal.text)
                        }
                    case "maxLength":
                        if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                            maxLength = Int(intLiteral.literal.text)
                        }
                    case "pattern":
                        if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            pattern = segment.content.text
                        }
                    case "format":
                        if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            format = segment.content.text
                        }
                    case "enum":
                        enumValues = extractEnumValues(from: argument.expression)
                    case "maxItems":
                        if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                            maxItems = Int(intLiteral.literal.text)
                        }
                    default:
                        break
                    }
                }
            }
            
            return FieldMetadata(
                description: description,
                minValue: minValue,
                maxValue: maxValue,
                minLength: minLength,
                maxLength: maxLength,
                pattern: pattern,
                format: format,
                enumValues: enumValues,
                maxItems: maxItems
            )
        }
        
        return nil
    }
    
    private static func extractEnumValues(from expression: ExprSyntax) -> [String]? {
        // Handle array literal expression
        if let arrayExpr = expression.as(ArrayExprSyntax.self) {
            var values: [String] = []
            for element in arrayExpr.elements {
                if let stringLiteral = element.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    values.append(segment.content.text)
                }
            }
            return values.isEmpty ? nil : values
        }
        return nil
    }
    
    private static func isOptionalType(_ type: String) -> Bool {
        return type.hasSuffix("?") || type.hasPrefix("Optional<")
    }
    
    private static func generateDescription(_ typeName: String) -> String {
        return "\(typeName) object"
    }
    
    private static func generateSchemaProperty(
        typeName: String,
        properties: [PropertyInfo]
    ) throws -> VariableDeclSyntax {
        let schemaBody = generateSchemaBody(properties: properties)
        
        return try VariableDeclSyntax(
            """
            static var schema: ObjectSchema<\(raw: typeName)> {
                .define(description: "\(raw: generateDescription(typeName))") {
            \(raw: schemaBody)
                }
            }
            """
        )
    }
    
    private static func generateSchemaBody(properties: [PropertyInfo]) -> String {
        var lines: [String] = []
        
        for property in properties {
            let schemaLine = generateSchemaLine(for: property)
            lines.append("        \(schemaLine)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func generateSchemaLine(for property: PropertyInfo) -> String {
        let baseType = stripOptional(from: property.type)
        let isRequired = !property.isOptional
        
        var params: [String] = ["\"\(property.name)\""]
        
        // Add description if available
        if let description = property.fieldMetadata?.description {
            params.append("description: \"\(description)\"")
        }
        
        // Determine schema method based on type
        let schemaMethod: String
        switch baseType {
        case "String":
            schemaMethod = "string"
            if let minLength = property.fieldMetadata?.minLength {
                params.append("minLength: \(minLength)")
            }
            if let maxLength = property.fieldMetadata?.maxLength {
                params.append("maxLength: \(maxLength)")
            }
            if let pattern = property.fieldMetadata?.pattern {
                params.append("pattern: \"\(pattern)\"")
            }
            if let format = property.fieldMetadata?.format {
                params.append("format: \"\(format)\"")
            }
            if let enumValues = property.fieldMetadata?.enumValues {
                let enumList = enumValues.map { "\"\($0)\"" }.joined(separator: ", ")
                params.append("enum: [\(enumList)]")
            }
            
        case "Int":
            schemaMethod = "integer"
            if let minValue = property.fieldMetadata?.minValue {
                params.append("minimum: \(minValue)")
            }
            if let maxValue = property.fieldMetadata?.maxValue {
                params.append("maximum: \(maxValue)")
            }
            
        case "Double", "Float":
            schemaMethod = "number"
            if let minValue = property.fieldMetadata?.minValue {
                params.append("minimum: \(minValue)")
            }
            if let maxValue = property.fieldMetadata?.maxValue {
                params.append("maximum: \(maxValue)")
            }
            
        case "Bool":
            schemaMethod = "boolean"
            
        case "Date":
            schemaMethod = "date"
            
        case "URL":
            schemaMethod = "url"
            
        case "UUID":
            schemaMethod = "uuid"
            
        default:
            // Handle arrays
            if baseType.hasPrefix("[") && baseType.hasSuffix("]") {
                let elementType = String(baseType.dropFirst().dropLast())
                schemaMethod = "array"
                
                // For simple types, use elementSchema parameter
                if isSimpleType(elementType) {
                    let elementSchema = schemaForSimpleType(elementType)
                    // elementSchema should come after the key name (position 1)
                    params.insert("elementSchema: .\(elementSchema)", at: 1)
                } else {
                    // For complex types, assume they conform to SchemaProviding
                    params.insert("of: \(elementType).self", at: 1)
                }
                
                if let maxItems = property.fieldMetadata?.maxItems {
                    params.append("maxItems: \(maxItems)")
                }
            } else if baseType.contains(".") {
                // Check if it's an enum type (has dot notation)
                // For now, treat enums as strings
                schemaMethod = "string"
            } else {
                // Check if the type name starts with uppercase (likely a custom type)
                // For types that might be enums, we should use string schema
                if isLikelyEnumType(baseType) {
                    schemaMethod = "string"
                } else {
                    // Assume it's a custom type that conforms to SchemaProviding
                    schemaMethod = "object"
                    params.insert("of: \(baseType).self", at: 1)
                }
            }
        }
        
        // Add required parameter
        params.append("required: \(isRequired)")
        
        return "Schema.\(schemaMethod)(\(params.joined(separator: ", ")))"
    }
    
    private static func isLikelyEnumType(_ type: String) -> Bool {
        // Simple heuristic: if it's a single word starting with uppercase and
        // not one of our known types, it might be an enum
        let knownTypes = ["String", "Int", "Double", "Float", "Bool", "Date", "URL", "UUID"]
        return !knownTypes.contains(type) && 
               type.first?.isUppercase == true && 
               !type.contains("<") && 
               !type.contains(".")
    }
    
    private static func stripOptional(from type: String) -> String {
        if type.hasSuffix("?") {
            return String(type.dropLast())
        } else if type.hasPrefix("Optional<") && type.hasSuffix(">") {
            return String(type.dropFirst("Optional<".count).dropLast())
        }
        return type
    }
    
    private static func isSimpleType(_ type: String) -> Bool {
        return ["String", "Int", "Double", "Float", "Bool", "Date", "URL", "UUID"].contains(type)
    }
    
    private static func schemaForSimpleType(_ type: String) -> String {
        switch type {
        case "String": return "string()"
        case "Int": return "integer()"
        case "Double", "Float": return "number()"
        case "Bool": return "boolean()"
        case "Date": return "string(format: \"date-time\")"
        case "URL": return "string(format: \"uri\")"
        case "UUID": return "string(format: \"uuid\")"
        default: return "string()"
        }
    }
    
    private static func generatePartialType(
        typeName: String,
        properties: [PropertyInfo]
    ) throws -> StructDeclSyntax {
        var members: [String] = []
        
        // Generate optional properties
        for property in properties {
            let optionalType = makeOptional(property.type)
            members.append("    public let \(property.name): \(optionalType)")
        }
        
        // Add field status tracking
        members.append("    private let _fieldStatus: [String: FieldStatus]")
        
        // Add public initializer
        let initMethod = generatePartialInitializer(properties: properties)
        members.append("")
        members.append(initMethod)
        
        // Add complete() method
        let completeMethod = generateCompleteMethod(typeName: typeName, properties: properties)
        members.append("")
        members.append(completeMethod)
        
        // Add isFieldComplete() method
        members.append("")
        members.append("    public func isFieldComplete(_ field: String) -> Bool {")
        members.append("        _fieldStatus[field] == .completed")
        members.append("    }")
        
        let structBody = members.joined(separator: "\n")
        
        return try StructDeclSyntax(
            """
            public struct Partial {
            \(raw: structBody)
            }
            """
        )
    }
    
    private static func makeOptional(_ type: String) -> String {
        if type.hasSuffix("?") || type.hasPrefix("Optional<") {
            return type
        }
        return "\(type)?"
    }
    
    private static func generatePartialInitializer(properties: [PropertyInfo]) -> String {
        var params: [String] = []
        var assignments: [String] = []
        
        for property in properties {
            let optionalType = makeOptional(property.type)
            params.append("\(property.name): \(optionalType)")
            assignments.append("        self.\(property.name) = \(property.name)")
        }
        
        params.append("_fieldStatus: [String: FieldStatus]")
        assignments.append("        self._fieldStatus = _fieldStatus")
        
        let paramString = params.joined(separator: ",\n        ")
        let assignmentString = assignments.joined(separator: "\n    ")
        
        var lines: [String] = []
        lines.append("    public init(")
        lines.append("        \(paramString)")
        lines.append("    ) {")
        lines.append("    \(assignmentString)")
        lines.append("    }")
        
        return lines.joined(separator: "\n")
    }
    
    private static func generateCompleteMethod(typeName: String, properties: [PropertyInfo]) -> String {
        var guardConditions: [String] = []
        var missingChecks: [String] = []
        var initParams: [String] = []
        
        for property in properties {
            if !property.isOptional {
                guardConditions.append("let \(property.name) = \(property.name)")
                missingChecks.append("\(property.name) == nil ? \"\(property.name)\" : nil")
            }
            initParams.append("\(property.name): \(property.name)")
        }
        
        var lines: [String] = []
        lines.append("    public func complete() throws -> \(typeName) {")
        
        if !guardConditions.isEmpty {
            lines.append("        guard \(guardConditions.joined(separator: ",\n              ")) else {")
            lines.append("            let missing = [")
            for (index, check) in missingChecks.enumerated() {
                if index == missingChecks.count - 1 {
                    lines.append("                \(check)")
                } else {
                    lines.append("                \(check),")
                }
            }
            lines.append("            ].compactMap { $0 }")
            lines.append("            ")
            lines.append("            throw IncompleteObjectError(")
            lines.append("                missingFields: missing,")
            lines.append("                presentFields: _fieldStatus.compactMapValues { $0 == .completed ? $0 : nil }.keys.sorted()")
            lines.append("            )")
            lines.append("        }")
            lines.append("        ")
        }
        
        lines.append("        return \(typeName)(\(initParams.joined(separator: ", ")))")
        lines.append("    }")
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

struct PropertyInfo {
    let name: String
    let type: String
    let fieldMetadata: FieldMetadata?
    let isOptional: Bool
}

struct FieldMetadata {
    let description: String?
    let minValue: String?
    let maxValue: String?
    let minLength: Int?
    let maxLength: Int?
    let pattern: String?
    let format: String?
    let enumValues: [String]?
    let maxItems: Int?
}

// MARK: - Error Types

enum AIModelMacroError: Error, CustomStringConvertible {
    case notAStructOrClass
    case missingTypeAnnotation(property: String)
    
    var description: String {
        switch self {
        case .notAStructOrClass:
            return "@AIModel can only be applied to structs or classes"
        case .missingTypeAnnotation(let property):
            return "Property '\(property)' must have an explicit type annotation"
        }
    }
}

// MARK: - Field Macro

/// The @Field macro for annotating properties with metadata
public struct FieldMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // @Field doesn't generate any code, it's just metadata
        return []
    }
}

// MARK: - Field Status for Partial Types

public enum FieldStatus {
    case notStarted
    case inProgress
    case completed
}