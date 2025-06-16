import Foundation
import Testing
@testable import ai_swift

/// Comprehensive unit tests for JSON parsing and extraction utilities
/// 
/// These tests validate the critical JSON extraction logic that caused widespread
/// test failures when the array/object priority was incorrect. The tests ensure:
/// 1. Correct JSON boundary detection for objects vs arrays
/// 2. Context-aware extraction based on expected type
/// 3. Robust handling of edge cases and malformed content
@Suite("JSON Parsing and Extraction Tests")
struct JSONParsingTests {
    
    // MARK: - extractJSONFromResponse Tests
    
    @Test("Extract simple JSON object")
    func testExtractSimpleObject() throws {
        let input = """
        Here's your JSON response:
        {
            "name": "Test",
            "value": 42
        }
        Hope that helps!
        """
        
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: false)
        let expected = """
        {
            "name": "Test",
            "value": 42
        }
        """
        
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == 
               expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    @Test("Extract simple JSON array")
    func testExtractSimpleArray() throws {
        let input = """
        Here's your array:
        [
            {"name": "Item1"},
            {"name": "Item2"}
        ]
        That's all!
        """
        
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: true)
        let expected = """
        [
            {"name": "Item1"},
            {"name": "Item2"}
        ]
        """
        
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == 
               expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    @Test("Priority: Object with array field - expect object")
    func testObjectWithArrayFieldExpectingObject() throws {
        let input = """
        {
            "name": "Recipe",
            "ingredients": ["pasta", "sauce", "cheese"],
            "cookingTime": 20
        }
        """
        
        // This was the original bug - it would extract ["pasta", "sauce", "cheese"] instead of the full object
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: false)
        
        #expect(result.contains("\"name\": \"Recipe\""))
        #expect(result.contains("\"cookingTime\": 20"))
        #expect(result.hasPrefix("{"))
        #expect(result.hasSuffix("}"))
    }
    
    @Test("Priority: Array at document start - expect array")
    func testArrayAtStartExpectingArray() throws {
        let input = """
        [
            {
                "name": "Product1",
                "price": 99.99
            },
            {
                "name": "Product2", 
                "price": 49.99
            }
        ]
        """
        
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: true)
        
        #expect(result.hasPrefix("["))
        #expect(result.hasSuffix("]"))
        #expect(result.contains("Product1"))
        #expect(result.contains("Product2"))
    }
    
    @Test("Fallback: Object expected but array found")
    func testFallbackObjectExpectedArrayFound() throws {
        let input = """
        [{"item": "test"}]
        """
        
        // When expecting object but only array available, should fall back to array
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: false)
        
        #expect(result == "[{\"item\": \"test\"}]")
    }
    
    @Test("Fallback: Array expected but object found")
    func testFallbackArrayExpectedObjectFound() throws {
        let input = """
        {"items": ["test1", "test2"]}
        """
        
        // When expecting array but only object available, should fall back to object
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: true)
        
        #expect(result == "{\"items\": [\"test1\", \"test2\"]}")
    }
    
    @Test("Nested structures with multiple braces/brackets")
    func testNestedStructures() throws {
        let input = """
        {
            "data": {
                "items": [
                    {"id": 1, "tags": ["a", "b"]},
                    {"id": 2, "nested": {"key": "value"}}
                ]
            },
            "meta": {"count": 2}
        }
        """
        
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: false)
        
        // Should extract the complete outer object, not any nested array
        #expect(result.hasPrefix("{"))
        #expect(result.hasSuffix("}"))
        #expect(result.contains("\"data\""))
        #expect(result.contains("\"meta\""))
        
        // Verify it's valid JSON by attempting to parse
        let data = result.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data)
        #expect(parsed is [String: Any])
    }
    
    @Test("Malformed JSON - missing closing brace")
    func testMalformedJSONMissingBrace() throws {
        let input = """
        {
            "name": "Test",
            "value": 42
        // Missing closing brace
        """
        
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: false)
        
        // Should return original content when malformed
        #expect(result == input)
    }
    
    @Test("Multiple JSON objects - extract first")
    func testMultipleJSONObjects() throws {
        let input = """
        {"first": "object"} and then {"second": "object"}
        """
        
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: false)
        
        #expect(result == "{\"first\": \"object\"}")
    }
    
    @Test("No JSON content")
    func testNoJSONContent() throws {
        let input = "This is just plain text with no JSON"
        
        let result = JSONTestHelpers.extractJSONFromResponse(input, expectingArray: false)
        
        #expect(result == input)
    }
    
    // MARK: - isArrayType Tests
    
    @Test("Detect string array type")
    func testIsArrayTypeString() throws {
        let isArray = JSONTestHelpers.isArrayType([String].self)
        
        #expect(isArray == true)
    }
    
    @Test("Detect custom struct array type")
    func testIsArrayTypeCustomStruct() throws {
        struct TestStruct: Codable {
            let name: String
        }
        
        let isArray = JSONTestHelpers.isArrayType([TestStruct].self)
        
        #expect(isArray == true)
    }
    
    @Test("Detect non-array string type")
    func testIsNotArrayTypeString() throws {
        let isArray = JSONTestHelpers.isArrayType(String.self)
        
        #expect(isArray == false)
    }
    
    @Test("Detect non-array custom struct type")
    func testIsNotArrayTypeCustomStruct() throws {
        struct TestStruct: Codable {
            let name: String
        }
        
        let isArray = JSONTestHelpers.isArrayType(TestStruct.self)
        
        #expect(isArray == false)
    }
    
    @Test("Detect nested array type")
    func testIsArrayTypeNested() throws {
        let isArray = JSONTestHelpers.isArrayType([[String]].self)
        
        #expect(isArray == true)
    }
    
    // MARK: - parseJSONResponse Integration Tests
    
    @Test("Parse JSON response with object type")
    func testParseJSONResponseObject() async throws {
        struct TestObject: Codable {
            let name: String
            let value: Int
        }
        
        let client = AIClient()
        let input = """
        Extra text before
        {
            "name": "Test",
            "value": 42
        }
        Extra text after
        """
        
        let result: TestObject = try await client.parseJSONResponse(input, as: TestObject.self)
        
        #expect(result.name == "Test")
        #expect(result.value == 42)
    }
    
    @Test("Parse JSON response with array type")
    func testParseJSONResponseArray() async throws {
        struct TestItem: Codable {
            let id: Int
            let name: String
        }
        
        let client = AIClient()
        let input = """
        Here's your array:
        [
            {"id": 1, "name": "First"},
            {"id": 2, "name": "Second"}
        ]
        Done!
        """
        
        let result: [TestItem] = try await client.parseJSONResponse(input, as: [TestItem].self)
        
        #expect(result.count == 2)
        #expect(result[0].id == 1)
        #expect(result[0].name == "First")
        #expect(result[1].id == 2)
        #expect(result[1].name == "Second")
    }
    
    @Test("Parse JSON response with object containing array field")
    func testParseJSONResponseObjectWithArrayField() async throws {
        struct Recipe: Codable {
            let name: String
            let ingredients: [String]
            let cookingTime: Int
        }
        
        let client = AIClient()
        let input = """
        {
            "name": "Simple Pasta",
            "ingredients": ["pasta", "tomato sauce", "cheese"],
            "cookingTime": 20
        }
        """
        
        // This specific case was the original bug - should parse successfully
        let result: Recipe = try await client.parseJSONResponse(input, as: Recipe.self)
        
        #expect(result.name == "Simple Pasta")
        #expect(result.ingredients == ["pasta", "tomato sauce", "cheese"])
        #expect(result.cookingTime == 20)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Parse invalid JSON throws error")
    func testParseInvalidJSONThrowsError() async throws {
        struct TestObject: Codable {
            let name: String
        }
        
        let client = AIClient()
        let input = """
        {
            "name": "Test"
            // Missing comma and malformed
            "value": 42
        """
        
        await #expect(throws: AIGenerationError.self) {
            let _: TestObject = try await client.parseJSONResponse(input, as: TestObject.self)
        }
    }
    
    @Test("Parse wrong structure throws error")
    func testParseWrongStructureThrowsError() async throws {
        struct TestObject: Codable {
            let name: String
            let value: Int
        }
        
        let client = AIClient()
        let input = """
        {
            "name": "Test"
            // Missing required 'value' field
        }
        """
        
        await #expect(throws: AIGenerationError.self) {
            let _: TestObject = try await client.parseJSONResponse(input, as: TestObject.self)
        }
    }
}

// MARK: - Test Helper Utilities

/// Static helper functions for testing JSON parsing logic without actor context
struct JSONTestHelpers {
    
    /// Check if a type is an array type
    static func isArrayType<T>(_ type: T.Type) -> Bool {
        return String(describing: type).hasPrefix("Array<") || String(describing: type).contains("[]")
    }
    
    /// Extract JSON content from response text that might contain additional content
    /// This mirrors the implementation in AIClient+JSONParsing.swift for testing
    static func extractJSONFromResponse(_ content: String, expectingArray: Bool = false) -> String {
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