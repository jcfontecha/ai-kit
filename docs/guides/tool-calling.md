# Tool Calling Guide

This guide covers how to integrate and use tools (function calling) with AIKit, enabling models to interact with external systems and APIs.

## Overview

Tool calling allows AI models to request execution of specific functions to retrieve information or perform actions. AIKit provides automatic tool execution during text generation and streaming, following the same pattern as Vercel AI SDK.

## Basic Tool Definition

Tools in AIKit consist of:
1. A function definition (name, description, parameters)
2. An execute function that runs when the model calls the tool

```swift
import AIKit

let weatherTool = Tool(
    function: ToolFunction(
        name: "get_weather",
        description: "Get current weather for a location",
        parameters: JSONSchema.object(properties: [
            "location": .string(description: "City and state, e.g. San Francisco, CA"),
            "units": .string(enum: ["celsius", "fahrenheit"], description: "Temperature units")
        ], required: ["location"])
    ),
    execute: { toolCall in
        // Extract parameters from the tool call
        let args = toolCall.function.parsedArguments ?? [:]
        let location = args["location"] as? String ?? "Unknown"
        let units = args["units"] as? String ?? "celsius"
        
        // Perform the actual work (API call, database query, etc.)
        let temperature = units == "celsius" ? "22°C" : "72°F"
        
        // Return the result
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text("The weather in \(location) is \(temperature) and sunny")
        )
    }
)
```

## Using Tools with Text Generation

### Automatic Tool Execution

When you provide tools to `generateText` or `streamText`, AIKit automatically executes them when the model requests:

```swift
let response = try await client.generateText(
    model,
    messages: [Message.user("What's the weather in Tokyo?")],
    tools: [weatherTool]
)

// The model will:
// 1. Recognize it needs weather information
// 2. Call the weather tool with location="Tokyo"
// 3. Receive the tool result
// 4. Generate a final response incorporating the information

print(response.text) 
// Output: "The weather in Tokyo is 22°C and sunny."
```

### Multiple Tools

You can provide multiple tools, and the model will choose which ones to use:

```swift
let calculatorTool = Tool(
    function: ToolFunction(
        name: "calculate",
        description: "Perform mathematical calculations",
        parameters: JSONSchema.object(properties: [
            "expression": .string(description: "Mathematical expression to evaluate")
        ], required: ["expression"])
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let expression = args["expression"] as? String ?? ""
        
        // Evaluate the expression (simplified example)
        let result = evaluateExpression(expression)
        
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text("Result: \(result)")
        )
    }
)

let response = try await client.generateText(
    model,
    messages: [Message.user("What's the weather in Paris and what's 25 * 4?")],
    tools: [weatherTool, calculatorTool]
)
```

## Tool Definition with SchemaProviding

For more complex parameter schemas, use the SchemaProviding protocol:

```swift
struct DatabaseQuery: SchemaProviding {
    let table: String
    let filters: [String: String]
    let limit: Int
    let orderBy: String?
    
    static var schema: ObjectSchema<DatabaseQuery> {
        .define(description: "Database query parameters") {
            Schema.string("table", description: "Table name", enum: ["users", "posts", "comments"])
            Schema.object("filters", description: "Filter conditions")
            Schema.integer("limit", description: "Maximum results", minimum: 1, maximum: 1000)
            Schema.string("orderBy", description: "Sort column", required: false)
        }
    }
}

let databaseTool = Tool(
    function: ToolFunction(
        name: "query_database",
        description: "Query the application database",
        parameters: DatabaseQuery.schema.jsonSchema
    ),
    execute: { toolCall in
        // Parse the structured parameters
        if let queryData = toolCall.function.parsedArguments,
           let jsonData = try? JSONSerialization.data(withJSONObject: queryData),
           let query = try? JSONDecoder().decode(DatabaseQuery.self, from: jsonData) {
            
            // Execute database query
            let results = executeQuery(table: query.table, filters: query.filters, limit: query.limit)
            
            return ToolResult(
                toolCallId: toolCall.id,
                result: .text("Found \(results.count) records")
            )
        }
        
        return ToolResult.error(toolCallId: toolCall.id, error: "Invalid query parameters")
    }
)
```

## Streaming with Tools

Tools work seamlessly with streaming, executing automatically as needed:

```swift
let stream = client.streamText(
    model,
    messages: [Message.user("Find information about Swift programming and calculate its age")],
    tools: [searchTool, calculatorTool],
    maxSteps: 3  // Allow up to 3 tool executions
)

// The stream will include:
// 1. Initial model text
// 2. Tool call events
// 3. Tool execution results
// 4. Final response incorporating all information

for try await chunk in stream {
    if let toolCall = chunk.toolCallStreamingStart {
        print("Calling tool: \(toolCall.toolName)")
    }
    
    print(chunk.delta, terminator: "")
}
```

## Advanced Tool Patterns

### Error Handling in Tools

```swift
let robustTool = Tool(
    function: ToolFunction(
        name: "fetch_data",
        description: "Fetch data from external API",
        parameters: JSONSchema.object(properties: [
            "endpoint": .string()
        ], required: ["endpoint"])
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let endpoint = args["endpoint"] as? String ?? ""
        
        do {
            let data = try await fetchFromAPI(endpoint: endpoint)
            return ToolResult(
                toolCallId: toolCall.id,
                result: .text(data)
            )
        } catch {
            // Return error result
            return ToolResult.error(
                toolCallId: toolCall.id,
                error: "Failed to fetch data: \(error.localizedDescription)"
            )
        }
    }
)
```

### Async Tool Execution

All tool execute functions are async, allowing for network calls and other async operations:

```swift
let asyncTool = Tool(
    function: ToolFunction(
        name: "translate_text",
        description: "Translate text to another language",
        parameters: JSONSchema.object(properties: [
            "text": .string(),
            "targetLanguage": .string(enum: ["es", "fr", "de", "ja"])
        ], required: ["text", "targetLanguage"])
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let text = args["text"] as? String ?? ""
        let targetLang = args["targetLanguage"] as? String ?? "en"
        
        // Async translation API call
        let translated = try await translationAPI.translate(
            text: text,
            to: targetLang
        )
        
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text(translated)
        )
    }
)
```

### Tool with Complex Results

Tools can return structured data that the model can interpret:

```swift
let analyticsTool = Tool(
    function: ToolFunction(
        name: "get_analytics",
        description: "Get website analytics data",
        parameters: JSONSchema.object(properties: [
            "metric": .string(enum: ["visitors", "pageviews", "bounce_rate"]),
            "period": .string(enum: ["day", "week", "month"])
        ], required: ["metric", "period"])
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let metric = args["metric"] as? String ?? "visitors"
        let period = args["period"] as? String ?? "day"
        
        let data = fetchAnalytics(metric: metric, period: period)
        
        // Return structured data as JSON string
        let jsonData = try JSONEncoder().encode(data)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text(jsonString)
        )
    }
)
```

## Tool Choice Control

Control how the model uses tools:

```swift
// Let the model decide (default)
let response1 = try await client.generateText(
    model,
    messages: messages,
    tools: tools,
    toolChoice: .auto
)

// Force a specific tool
let response2 = try await client.generateText(
    model,
    messages: messages,
    tools: tools,
    toolChoice: .tool(name: "get_weather")
)

// Require some tool to be used
let response3 = try await client.generateText(
    model,
    messages: messages,
    tools: tools,
    toolChoice: .required
)

// Prevent tool usage
let response4 = try await client.generateText(
    model,
    messages: messages,
    tools: tools,
    toolChoice: .none
)
```

## Best Practices

### 1. Clear Tool Descriptions

```swift
// ❌ Vague description
Tool(
    function: ToolFunction(
        name: "search",
        description: "Search for stuff",
        parameters: ...
    ),
    execute: ...
)

// ✅ Clear, specific description
Tool(
    function: ToolFunction(
        name: "search_documentation",
        description: "Search the Swift documentation for classes, methods, or concepts",
        parameters: ...
    ),
    execute: ...
)
```

### 2. Validate Parameters

```swift
execute: { toolCall in
    let args = toolCall.function.parsedArguments ?? [:]
    
    // Validate required parameters
    guard let query = args["query"] as? String, !query.isEmpty else {
        return ToolResult.error(
            toolCallId: toolCall.id,
            error: "Missing or empty query parameter"
        )
    }
    
    // Validate parameter values
    let limit = args["limit"] as? Int ?? 10
    guard limit > 0 && limit <= 100 else {
        return ToolResult.error(
            toolCallId: toolCall.id,
            error: "Limit must be between 1 and 100"
        )
    }
    
    // Proceed with execution
    let results = performSearch(query: query, limit: limit)
    return ToolResult(
        toolCallId: toolCall.id,
        result: .text("Found \(results.count) results")
    )
}
```

### 3. Handle Errors Gracefully

```swift
execute: { toolCall in
    do {
        let result = try await riskyOperation()
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text(result)
        )
    } catch NetworkError.timeout {
        return ToolResult.error(
            toolCallId: toolCall.id,
            error: "Operation timed out. Please try again."
        )
    } catch {
        // Log error for debugging
        logger.error("Tool execution failed: \(error)")
        
        // Return user-friendly error
        return ToolResult.error(
            toolCallId: toolCall.id,
            error: "Unable to complete the operation"
        )
    }
}
```

### 4. Use Sendable for Thread Safety

Since tool execute functions must be Sendable:

```swift
// Create a Sendable actor for shared state
actor ToolState {
    private var cache: [String: String] = [:]
    
    func getCached(key: String) -> String? {
        return cache[key]
    }
    
    func setCached(key: String, value: String) {
        cache[key] = value
    }
}

let toolState = ToolState()

let cachedTool = Tool(
    function: ToolFunction(...),
    execute: { toolCall in
        let key = toolCall.function.arguments
        
        // Check cache first
        if let cached = await toolState.getCached(key: key) {
            return ToolResult(
                toolCallId: toolCall.id,
                result: .text(cached)
            )
        }
        
        // Fetch and cache
        let result = try await fetchData(key: key)
        await toolState.setCached(key: key, value: result)
        
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text(result)
        )
    }
)
```

## Multi-Step Tool Execution

AIKit supports automatic multi-step tool execution:

```swift
// Define tools that might call each other
let searchTool = Tool(
    function: ToolFunction(
        name: "search",
        description: "Search for information",
        parameters: JSONSchema.object(properties: [
            "query": .string()
        ], required: ["query"])
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let query = args["query"] as? String ?? ""
        let results = performSearch(query)
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text("Found: \(results.joined(separator: ", "))")
        )
    }
)

let summarizeTool = Tool(
    function: ToolFunction(
        name: "summarize",
        description: "Summarize text content",
        parameters: JSONSchema.object(properties: [
            "text": .string()
        ], required: ["text"])
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let text = args["text"] as? String ?? ""
        let summary = generateSummary(text)
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text(summary)
        )
    }
)

// Model can use multiple tools in sequence
let response = try await client.generateText(
    model,
    messages: [Message.user("Search for Swift concurrency and summarize what you find")],
    tools: [searchTool, summarizeTool],
    maxSteps: 5  // Allow up to 5 tool executions
)

// The model will:
// 1. Call search tool with "Swift concurrency"
// 2. Get the search results
// 3. Call summarize tool with the results
// 4. Generate final response with the summary
```

## Testing Tools

```swift
import XCTest
@testable import AIKit

class ToolTests: XCTestCase {
    func testWeatherTool() async throws {
        let weatherTool = createWeatherTool()
        
        // Create a mock tool call
        let toolCall = ToolCall(
            id: "test_123",
            function: ToolCallFunction(
                name: "get_weather",
                arguments: """
                {"location": "London", "units": "celsius"}
                """
            )
        )
        
        // Execute the tool
        let result = try await weatherTool.execute!(toolCall)
        
        // Verify the result
        XCTAssertEqual(result.toolCallId, "test_123")
        XCTAssertTrue(result.isSuccess)
        
        if case .text(let text) = result.result {
            XCTAssertTrue(text.contains("London"))
            XCTAssertTrue(text.contains("°C"))
        } else {
            XCTFail("Expected text result")
        }
    }
}
```

## See Also

- [Text Generation](text-generation.md) - Using tools with text generation
- [Streaming](streaming.md) - Tools in streaming contexts
- [API Reference](../api-reference/ai-client.md) - Complete API documentation