import Foundation

// MARK: - JSON Parsing Utilities

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension AIClient {
    
    /// Parse JSON response content into the specified type with proper error handling
    func parseJSONResponse<T: Codable>(_ content: String, as type: T.Type) throws -> T {
        // Extract JSON from the response content
        // Some providers might include extra text, so we need to find the JSON portion
        let jsonString = extractJSONFromResponse(content, expectingArray: isArrayType(type))
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIGenerationError.jsonParseError(
                text: content,
                parseError: NSError(domain: "AIClient", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not convert response to UTF-8 data"
                ])
            )
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: jsonData)
        } catch let decodingError as DecodingError {
            throw AIGenerationError.jsonParseError(
                text: content,
                parseError: decodingError
            )
        } catch {
            throw AIGenerationError.jsonParseError(
                text: content, 
                parseError: error
            )
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