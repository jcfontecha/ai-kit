import Foundation
@testable import AIKit

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
struct ImageSupportExample {
    
    /// Example: Using images with AIKit (following Vercel AI SDK patterns)
    static func demonstrateImageSupport() async throws {
        // Initialize provider and client
        let provider = OpenAIProvider(apiKey: "your-api-key")
        let model = provider.languageModel("gpt-4o-mini") // Vision-capable model
        let client = AIClient()
        
        // Example 1: Image from Data
        let imageData = try Data(contentsOf: URL(fileURLWithPath: "path/to/image.jpg"))
        let imageContent1 = ImageContent.data(imageData, mimeType: "image/jpeg")
        let response1 = try await client.generateText(
            model,
            messages: [CoreMessage.user("What's in this image?", image: imageContent1)]
        )
        print("Response: \(response1.text)")
        
        // Example 2: Image from URL
        let imageURL = URL(string: "https://example.com/image.png")!
        let imageContent2 = ImageContent.url(imageURL, mimeType: "image/png")
        let response2 = try await client.generateText(
            model,
            messages: [CoreMessage.user("Describe this image", image: imageContent2)]
        )
        print("Response: \(response2.text)")
        
        // Example 3: Multiple content parts (text + image + text)
        let message = CoreMessage(
            role: .user,
            content: [
                .text("I have a question about this image:"),
                .image(imageContent1),
                .text("What color is the main object?")
            ]
        )
        let response3 = try await client.generateText(model, messages: [message])
        print("Response: \(response3.text)")
        
        // Example 4: Streaming with images
        let result = await client.streamText(
            model,
            messages: [CoreMessage.user("Describe this image in detail", image: imageContent2)]
        )
        
        print("Streaming response: ", terminator: "")
        for try await chunk in result.textStream {
            print(chunk.delta, terminator: "")
        }
        print() // New line
    }
    
    /// Example: Using images in a conversation
    static func imageConversationExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        let model = provider.languageModel("gpt-4o-mini")
        let client = AIClient()
        
        // Build a conversation with images
        let messages = [
            CoreMessage.system("You are a helpful image analysis assistant."),
            CoreMessage.user(
                "Look at this cat image", 
                image: ImageContent.url(URL(string: "https://example.com/cat.jpg")!)
            ),
            CoreMessage.assistant("I can see a cat in the image. It appears to be..."),
            CoreMessage.user("What breed do you think it is?")
        ]
        
        let response = try await client.generateText(model, messages: messages)
        print("Assistant: \(response.text)")
    }
}