import Foundation

// MARK: - JSON Parsing Utilities

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension AIClient {
    
    /// Parse JSON response content into the specified type with proper error handling
    func parseJSONResponse<T: Codable>(_ content: String, as type: T.Type) throws -> T {
        // Extract JSON from the response content
        // Some providers might include extra text, so we need to find the JSON portion
        let jsonString = extractJSONFromResponse(content)
        
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
    
    /// Extract JSON content from response text that might contain additional content
    func extractJSONFromResponse(_ content: String) -> String {
        // Look for JSON object boundaries
        if let startIndex = content.firstIndex(of: "{") {
            // Find the matching closing brace by counting braces
            var braceCount = 0
            var endIndex = startIndex
            
            for (index, char) in content[startIndex...].enumerated() {
                let currentIndex = content.index(startIndex, offsetBy: index)
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = currentIndex
                        break
                    }
                }
            }
            
            if braceCount == 0 {
                return String(content[startIndex...endIndex])
            }
        }
        
        // If no valid JSON object found, return the original content
        return content
    }
}