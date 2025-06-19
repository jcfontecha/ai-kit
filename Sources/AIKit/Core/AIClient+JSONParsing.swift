import Foundation

// MARK: - JSON Parsing Utilities

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension AIClient {
    
    /// Parse JSON response content into the specified type with two-phase validation
    func parseJSONResponse<T: Codable>(_ content: String, as type: T.Type) throws -> T {
        // Phase 1: Safe JSON parsing (following Vercel AI SDK pattern)
        let parseResult = safeParseJSON(content, expectingArray: isArrayType(type))
        
        switch parseResult {
        case .success(let jsonData):
            // Phase 2: Safe type validation
            return try safeValidateTypes(jsonData, as: type)
        case .failure(let error):
            throw error
        }
    }
    
    /// Phase 1: Safe JSON parsing with detailed error context
    func safeParseJSON(_ content: String, expectingArray: Bool = false) -> Result<Data, AIGenerationError> {
        // Extract JSON from the response content
        let jsonString = extractJSONFromResponse(content, expectingArray: expectingArray)
        
        // Validate that we have valid JSON structure
        guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(AIGenerationError.jsonParseError(
                text: content,
                parseError: NSError(domain: "AIClient", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Empty JSON content after extraction"
                ])
            ))
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return .failure(AIGenerationError.jsonParseError(
                text: content,
                parseError: NSError(domain: "AIClient", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Could not convert response to UTF-8 data"
                ])
            ))
        }
        
        // Validate JSON syntax
        do {
            _ = try JSONSerialization.jsonObject(with: jsonData)
            return .success(jsonData)
        } catch {
            return .failure(AIGenerationError.jsonParseError(
                text: content,
                parseError: error
            ))
        }
    }
    
    /// Phase 2: Safe type validation with detailed error context
    func safeValidateTypes<T: Codable>(_ jsonData: Data, as type: T.Type) throws -> T {
        do {
            let decoder = createJSONDecoder()
            return try decoder.decode(T.self, from: jsonData)
        } catch let decodingError as DecodingError {
            // Enhanced decoding error with context
            throw AIGenerationError.schemaValidationError(
                objectData: String(data: jsonData, encoding: .utf8),
                validationErrors: [extractDecodingErrorMessage(decodingError)]
            )
        } catch {
            throw AIGenerationError.schemaValidationError(
                objectData: String(data: jsonData, encoding: .utf8),
                validationErrors: [error.localizedDescription]
            )
        }
    }
    
    /// Create configured JSON decoder
    private func createJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        
        // Configure decoder for better compatibility
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        
        // Allow case-insensitive key matching for better robustness
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return decoder
    }
    
    /// Extract meaningful error message from DecodingError
    private func extractDecodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Type mismatch at '\(path)': expected \(type), got different type"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Missing required value at '\(path)': expected \(type)"
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Missing required key '\(key.stringValue)' at '\(path)'"
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Corrupted data at '\(path)': \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error: \(error.localizedDescription)"
        }
    }
    
    /// Check if a type is an array type
    private func isArrayType<T>(_ type: T.Type) -> Bool {
        return String(describing: type).hasPrefix("Array<") || String(describing: type).contains("[]")
    }
    
    /// Extract JSON content from response text that might contain additional content
    func extractJSONFromResponse(_ content: String, expectingArray: Bool = false) -> String {
        // Find positions of potential JSON starts
        let objectStartIndex = content.firstIndex(of: "{")
        let arrayStartIndex = content.firstIndex(of: "[")
        
        if expectingArray {
            // When expecting an array, prioritize array extraction
            // But only if the array comes first in the document, or if there's no object
            let shouldExtractArray = arrayStartIndex != nil && (objectStartIndex == nil || arrayStartIndex! < objectStartIndex!)
            
            if shouldExtractArray, let startIndex = arrayStartIndex {
                var bracketCount = 0
                var arrayEndIndex = startIndex
                
                for (index, char) in content[startIndex...].enumerated() {
                    let currentIndex = content.index(startIndex, offsetBy: index)
                    if char == "[" {
                        bracketCount += 1
                    } else if char == "]" {
                        bracketCount -= 1
                        if bracketCount == 0 {
                            arrayEndIndex = currentIndex
                            break
                        }
                    }
                }
                
                if bracketCount == 0 {
                    return String(content[startIndex...arrayEndIndex])
                }
            }
            
            // Fall back to object extraction
            if let startIndex = objectStartIndex {
                var braceCount = 0
                var objectEndIndex = startIndex
                
                for (index, char) in content[startIndex...].enumerated() {
                    let currentIndex = content.index(startIndex, offsetBy: index)
                    if char == "{" {
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            objectEndIndex = currentIndex
                            break
                        }
                    }
                }
                
                if braceCount == 0 {
                    return String(content[startIndex...objectEndIndex])
                }
            }
        } else {
            // When expecting an object, prioritize object extraction
            // But only if the object comes first in the document, or if there's no array
            let shouldExtractObject = objectStartIndex != nil && (arrayStartIndex == nil || objectStartIndex! < arrayStartIndex!)
            
            if shouldExtractObject, let startIndex = objectStartIndex {
                var braceCount = 0
                var objectEndIndex = startIndex
                
                for (index, char) in content[startIndex...].enumerated() {
                    let currentIndex = content.index(startIndex, offsetBy: index)
                    if char == "{" {
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            objectEndIndex = currentIndex
                            break
                        }
                    }
                }
                
                if braceCount == 0 {
                    return String(content[startIndex...objectEndIndex])
                }
            }
            
            // Fall back to array extraction
            if let startIndex = arrayStartIndex {
                var bracketCount = 0
                var arrayEndIndex = startIndex
                
                for (index, char) in content[startIndex...].enumerated() {
                    let currentIndex = content.index(startIndex, offsetBy: index)
                    if char == "[" {
                        bracketCount += 1
                    } else if char == "]" {
                        bracketCount -= 1
                        if bracketCount == 0 {
                            arrayEndIndex = currentIndex
                            break
                        }
                    }
                }
                
                if bracketCount == 0 {
                    return String(content[startIndex...arrayEndIndex])
                }
            }
        }
        
        // If no valid JSON found, return the original content
        return content
    }
}