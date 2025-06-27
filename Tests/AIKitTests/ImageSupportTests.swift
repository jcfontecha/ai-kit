import XCTest
@testable import AIKit

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class ImageSupportTests: XCTestCase {
    
    // MARK: - Message Creation Tests
    
    func testCreateUserMessageWithImageData() {
        let imageData = Data("fake image data".utf8)
        let imageContent = ImageContent(data: imageData, mimeType: "image/jpeg")
        let message = CoreMessage.user("Describe this image", image: imageContent)
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content.count, 2)
        
        if case .text(let text) = message.content[0] {
            XCTAssertEqual(text, "Describe this image")
        } else {
            XCTFail("First content should be text")
        }
        
        if case .image(let img) = message.content[1] {
            XCTAssertEqual(img.data, imageData)
            XCTAssertEqual(img.mimeType, "image/jpeg")
        } else {
            XCTFail("Second content should be image")
        }
    }
    
    func testCreateUserMessageWithImageURL() {
        let imageURL = URL(string: "https://example.com/image.png")!
        let imageContent = ImageContent(url: imageURL, mimeType: "image/png")
        let message = CoreMessage.user("What's in this image?", image: imageContent)
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content.count, 2)
        
        if case .image(let img) = message.content[1] {
            XCTAssertEqual(img.url, imageURL)
            XCTAssertEqual(img.mimeType, "image/png")
        } else {
            XCTFail("Second content should be image")
        }
    }
    
    func testImageContentHelpers() {
        let data = Data("test".utf8)
        let url = URL(string: "https://example.com/test.jpg")!
        
        let dataImage = ImageContent.data(data)
        XCTAssertEqual(dataImage.data, data)
        XCTAssertNil(dataImage.url)
        XCTAssertEqual(dataImage.mimeType, "image/jpeg")
        
        let urlImage = ImageContent.url(url, mimeType: "image/png")
        XCTAssertEqual(urlImage.url, url)
        XCTAssertNil(urlImage.data)
        XCTAssertEqual(urlImage.mimeType, "image/png")
    }
    
    func testMessageWithMultipleImages() {
        let image1 = ImageContent.data(Data("image1".utf8))
        let image2 = ImageContent.url(URL(string: "https://example.com/image2.png")!)
        
        let message = CoreMessage(
            role: .user,
            content: [
                .text("Compare these two images:"),
                .image(image1),
                .text("and"),
                .image(image2)
            ]
        )
        
        XCTAssertEqual(message.content.count, 4)
        XCTAssertNotNil(message.content[0].textValue)
        XCTAssertNotNil(message.content[1].imageValue)
        XCTAssertNotNil(message.content[2].textValue)
        XCTAssertNotNil(message.content[3].imageValue)
    }
    
    // MARK: - Provider Integration Tests
    
    func testOpenAIProviderWithImageMessage() async throws {
        let mockProvider = MockProvider()
        let model = mockProvider.languageModel("test-model")
        let client = AIClient()
        
        let imageData = Data("test image".utf8)
        let imageContent = ImageContent.data(imageData, mimeType: "image/png")
        let messages = [CoreMessage.user("What's in this image?", image: imageContent)]
        
        let response = try await client.generateText(
            model,
            messages: messages
        )
        
        // Verify we got a response (MockProvider generates responses automatically)
        XCTAssertFalse(response.text.isEmpty, "Should have generated response text")
        XCTAssertEqual(response.messages.count, 2) // Original message + assistant response
        
        // Verify the input message structure was preserved
        if let userMessage = response.messages.first {
            XCTAssertEqual(userMessage.role, .user)
            XCTAssertEqual(userMessage.content.count, 2)
            XCTAssertNotNil(userMessage.content[0].textValue)
            XCTAssertNotNil(userMessage.content[1].imageValue)
        }
    }
    
    func testStreamingWithImageMessage() async throws {
        let mockProvider = MockProvider()
        let model = mockProvider.languageModel("test-model")
        let client = AIClient()
        
        let imageURL = URL(string: "https://example.com/test.jpg")!
        let imageContent = ImageContent.url(imageURL)
        let messages = [CoreMessage.user("Describe this image in detail", image: imageContent)]
        
        var fullText = ""
        var chunkCount = 0
        let stream = await client.streamText(model, messages: messages)
        
        for try await chunk in stream {
            fullText += chunk.delta
            chunkCount += 1
        }
        
        // MockProvider generates streaming responses automatically
        XCTAssertFalse(fullText.isEmpty, "Should have generated streaming response")
        XCTAssertGreaterThan(chunkCount, 1, "Should have multiple chunks")
    }
    
    // MARK: - Real Image File Tests
    
    func testLoadingRealImageFile() async throws {
        let testBundle = Bundle.module
        guard let imagePath = testBundle.path(forResource: "sample_image", ofType: "jpg") else {
            XCTFail("Could not find sample_image.jpg in test bundle")
            return
        }
        
        let imageURL = URL(fileURLWithPath: imagePath)
        let imageData = try Data(contentsOf: imageURL)
        
        // Verify we can load the image
        XCTAssertFalse(imageData.isEmpty)
        
        // Create message with real image data
        let imageContent = ImageContent.data(imageData, mimeType: "image/jpeg")
        let message = CoreMessage.user("What do you see in this image?", image: imageContent)
        
        XCTAssertEqual(message.content.count, 2)
        if case .image(let img) = message.content[1] {
            XCTAssertEqual(img.data, imageData)
            XCTAssertEqual(img.mimeType, "image/jpeg")
        }
    }
    
    func testBase64EncodingForImages() {
        let imageData = Data("test image data".utf8)
        let base64String = imageData.base64EncodedString()
        
        // Verify base64 encoding works
        XCTAssertFalse(base64String.isEmpty)
        
        // Verify we can decode it back
        if let decodedData = Data(base64Encoded: base64String) {
            XCTAssertEqual(decodedData, imageData)
        } else {
            XCTFail("Failed to decode base64 string")
        }
    }
    
    func testMultipleRealImagesInMessage() async throws {
        // Load both sample images
        let testBundle = Bundle.module
        guard let catImagePath = testBundle.path(forResource: "sample_image", ofType: "jpg"),
              let dogImagePath = testBundle.path(forResource: "sample_image_2", ofType: "jpg") else {
            XCTFail("Could not find sample images in test bundle")
            return
        }
        
        let catImageData = try Data(contentsOf: URL(fileURLWithPath: catImagePath))
        let dogImageData = try Data(contentsOf: URL(fileURLWithPath: dogImagePath))
        
        // Create message with multiple images and text
        let message = CoreMessage(
            role: .user,
            content: [
                .text("First image:"),
                .image(ImageContent.data(catImageData, mimeType: "image/jpeg")),
                .text("Second image:"),
                .image(ImageContent.data(dogImageData, mimeType: "image/jpeg")),
                .text("What do you see?")
            ]
        )
        
        // Verify message structure
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content.count, 5)
        
        // Verify content types in order
        XCTAssertNotNil(message.content[0].textValue)
        XCTAssertEqual(message.content[0].textValue, "First image:")
        
        XCTAssertNotNil(message.content[1].imageValue)
        XCTAssertEqual(message.content[1].imageValue?.data, catImageData)
        
        XCTAssertNotNil(message.content[2].textValue)
        XCTAssertEqual(message.content[2].textValue, "Second image:")
        
        XCTAssertNotNil(message.content[3].imageValue)
        XCTAssertEqual(message.content[3].imageValue?.data, dogImageData)
        
        XCTAssertNotNil(message.content[4].textValue)
        XCTAssertEqual(message.content[4].textValue, "What do you see?")
        
        // Verify both images are properly loaded
        XCTAssertGreaterThan(catImageData.count, 1000, "Cat image should have substantial data")
        XCTAssertGreaterThan(dogImageData.count, 1000, "Dog image should have substantial data")
    }
}

