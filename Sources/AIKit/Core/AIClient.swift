import Foundation

// MARK: - AIClient

/// The concrete framework that executes all AI operations and contains the core logic.
///
/// AIClient is the primary interface for interacting with AI models in the Swift AI SDK.
/// It follows the Vercel AI SDK patterns while being thoroughly Swift-native, using actors
/// for concurrency safety and providing type-safe interfaces for all operations.
///
/// ## Responsibilities
/// - Coordinate all AI operations through specialized extensions
/// - Manage middleware chain for request/response transformation
/// - Provide centralized tool execution coordination
/// - Maintain actor-based concurrency safety
/// - Serve as the main orchestration layer
///
/// ## Usage Examples
///
/// ### Simple Text Generation
/// ```swift
/// let client = AIClient()
/// let model = provider.languageModel("gpt-4")
/// let response = try await client.generateText(model, prompt: "Explain quantum computing")
/// ```
///
/// ### Streaming with Tools
/// ```swift
/// let stream = client.streamText(model, prompt: "What's the weather today?")
/// for try await chunk in stream {
///     print(chunk.delta, terminator: "")
/// }
/// ```
///
/// ### Object Generation
/// ```swift
/// let response = try await client.generateObject(
///     model,
///     prompt: "Create a recipe",
///     schema: ObjectSchema<Recipe>()
/// )
/// let recipe: Recipe = response.object
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public actor AIClient {
    
    // MARK: - Properties
    
    /// The middleware chain applied to all requests and responses
    internal let middleware: [any AIMiddleware]
    
    /// Optional tool executor provided by the caller for custom tool execution
    internal let toolExecutor: ((ToolCall) async throws -> ToolResult)?
    
    // MARK: - Initialization
    
    /// Creates a new AIClient with optional middleware chain and tool executor.
    ///
    /// - Parameters:
    ///   - middleware: Array of middleware to apply to requests and responses.
    ///     Middleware is applied in order for requests and reverse order for responses.
    ///   - toolExecutor: Optional custom tool executor provided by the caller.
    ///     If provided, this will be used instead of the default hardcoded tool execution.
    public init(middleware: [any AIMiddleware] = [], toolExecutor: ((ToolCall) async throws -> ToolResult)? = nil) {
        self.middleware = middleware
        self.toolExecutor = toolExecutor
    }
}