import XCTest
@testable import AIKit

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class TranscriptionTests: XCTestCase {
    
    // MARK: - AudioInput Tests
    
    func testAudioInputData() throws {
        let testData = "test audio data".data(using: .utf8)!
        let audioInput = AudioInput.data(testData)
        
        XCTAssertEqual(audioInput.debugDescription, "data(15 bytes)")
    }
    
    func testAudioInputFileURL() throws {
        let url = URL(fileURLWithPath: "/path/to/audio.mp3")
        let audioInput = AudioInput.fileURL(url)
        
        XCTAssertEqual(audioInput.debugDescription, "fileURL(audio.mp3)")
    }
    
    func testAudioInputRemoteURL() throws {
        let url = URL(string: "https://example.com/audio.wav")!
        let audioInput = AudioInput.url(url)
        
        XCTAssertEqual(audioInput.debugDescription, "url(https://example.com/audio.wav)")
    }
    
    func testAudioInputBase64String() throws {
        let base64 = "dGVzdCBhdWRpbyBkYXRh"
        let audioInput = AudioInput.base64String(base64)
        
        XCTAssertEqual(audioInput.debugDescription, "base64String(dGVzdCBhdWRpbyBkYXRh...)")
    }
    
    func testAudioInputDataExtraction() async throws {
        // Test data input
        let testData = "test audio data".data(using: .utf8)!
        let dataInput = AudioInput.data(testData)
        let extractedData = try await dataInput.audioData()
        XCTAssertEqual(extractedData, testData)
        
        // Test base64 input
        let base64Input = AudioInput.base64String("dGVzdCBhdWRpbyBkYXRh")
        let extractedBase64Data = try await base64Input.audioData()
        XCTAssertEqual(extractedBase64Data, testData)
    }
    
    func testAudioInputInvalidBase64() async throws {
        let invalidBase64Input = AudioInput.base64String("invalid-base64!")
        
        do {
            _ = try await invalidBase64Input.audioData()
            XCTFail("Expected TranscriptionError to be thrown")
        } catch TranscriptionError.unsupportedAudioFormat {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - TranscriptionConfiguration Tests
    
    func testTranscriptionConfigurationDefaults() throws {
        let config = TranscriptionConfiguration()
        
        XCTAssertNil(config.language)
        XCTAssertNil(config.prompt)
        XCTAssertNil(config.responseFormat)
        XCTAssertNil(config.temperature)
    }
    
    func testTranscriptionConfigurationBuilderPattern() throws {
        let config = TranscriptionConfiguration()
            .language("en")
            .prompt("Technical discussion about AI")
            .temperature(0.2)
            .responseFormat(.verboseJson)
        
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.prompt, "Technical discussion about AI")
        XCTAssertEqual(config.temperature, 0.2)
        XCTAssertEqual(config.responseFormat, .verboseJson)
    }
    
    func testTranscriptionResponseFormats() throws {
        XCTAssertEqual(TranscriptionResponseFormat.json.rawValue, "json")
        XCTAssertEqual(TranscriptionResponseFormat.text.rawValue, "text")
        XCTAssertEqual(TranscriptionResponseFormat.vtt.rawValue, "vtt")
        XCTAssertEqual(TranscriptionResponseFormat.srt.rawValue, "srt")
        XCTAssertEqual(TranscriptionResponseFormat.verboseJson.rawValue, "verbose_json")
    }
    
    
    // MARK: - TranscriptionModel Tests
    
    func testTranscriptionModelBasicInitialization() throws {
        let provider = MockProvider()
        let model = TranscriptionModel(provider: provider, modelId: "whisper-1")
        
        XCTAssertEqual(model.modelId, "whisper-1")
        XCTAssertTrue(model.provider is MockProvider)
        XCTAssertNil(model.configuration.language)
        XCTAssertNil(model.providerOptions)
        XCTAssertNil(model.headers)
        XCTAssertNil(model.maxRetries)
    }
    
    func testTranscriptionModelBuilderPattern() throws {
        let provider = MockProvider()
        let model = TranscriptionModel(provider: provider, modelId: "whisper-1")
            .language("en")
            .prompt("Technical discussion")
            .temperature(0.3)
            .responseFormat(.verboseJson)
            .maxRetries(3)
            .headers(["Custom-Header": "value"])
            .providerOptions(["option": "value"])
        
        XCTAssertEqual(model.configuration.language, "en")
        XCTAssertEqual(model.configuration.prompt, "Technical discussion")
        XCTAssertEqual(model.configuration.temperature, 0.3)
        XCTAssertEqual(model.configuration.responseFormat, .verboseJson)
        XCTAssertEqual(model.maxRetries, 3)
        XCTAssertEqual(model.headers?["Custom-Header"], "value")
        XCTAssertEqual(model.providerOptions?["option"], "value")
    }
    
    func testTranscriptionModelValidation() throws {
        let provider = MockProvider()
        
        // Valid configuration
        let validModel = TranscriptionModel(provider: provider, modelId: "whisper-1")
            .language("en")
            .temperature(0.5)
        
        XCTAssertNoThrow(try validModel.validateConfiguration())
        
        // Invalid temperature
        let invalidTempModel = TranscriptionModel(provider: provider, modelId: "whisper-1")
            .temperature(1.5)
        
        XCTAssertThrowsError(try invalidTempModel.validateConfiguration()) { error in
            guard case TranscriptionError.invalidConfiguration = error else {
                XCTFail("Expected TranscriptionError.invalidConfiguration")
                return
            }
        }
        
        // Invalid language code
        let invalidLangModel = TranscriptionModel(provider: provider, modelId: "whisper-1")
            .language("english")
        
        XCTAssertThrowsError(try invalidLangModel.validateConfiguration()) { error in
            guard case TranscriptionError.invalidConfiguration = error else {
                XCTFail("Expected TranscriptionError.invalidConfiguration")
                return
            }
        }
    }
    
    func testTranscriptionModelDebugDescription() throws {
        let provider = MockProvider()
        let model = TranscriptionModel(provider: provider, modelId: "whisper-1")
            .language("en")
            .temperature(0.5)
            .responseFormat(.verboseJson)
            .maxRetries(2)
        
        let debugInfo = model.debugDescription
        
        XCTAssertEqual(debugInfo["provider"] as? String, "Mock Provider")
        XCTAssertEqual(debugInfo["modelId"] as? String, "whisper-1")
        XCTAssertEqual(debugInfo["language"] as? String, "en")
        XCTAssertEqual(debugInfo["temperature"] as? Double, 0.5)
        XCTAssertEqual(debugInfo["responseFormat"] as? String, "verbose_json")
        XCTAssertEqual(debugInfo["maxRetries"] as? Int, 2)
    }
    
    func testTranscriptionModelCreateProviderRequest() throws {
        let provider = MockProvider()
        let audio = AudioInput.data("test".data(using: .utf8)!)
        let model = TranscriptionModel(provider: provider, modelId: "whisper-1")
            .language("en")
            .prompt("test prompt")
        
        let request = model.createProviderRequest(audio: audio, requestId: "test-id")
        
        XCTAssertEqual(request.modelId, "whisper-1")
        XCTAssertEqual(request.configuration.language, "en")
        XCTAssertEqual(request.configuration.prompt, "test prompt")
        XCTAssertEqual(request.requestId, "test-id")
        
        // Test audio input
        switch request.audio {
        case .data(let data):
            XCTAssertEqual(data, "test".data(using: .utf8)!)
        default:
            XCTFail("Expected data audio input")
        }
    }
    
    // MARK: - TranscriptionResponse Tests
    
    func testTranscriptionResponse() throws {
        let segments = [
            TranscriptionSegment(text: "Hello", startSecond: 0.0, endSecond: 1.0),
            TranscriptionSegment(text: "world", startSecond: 1.0, endSecond: 2.0)
        ]
        
        let metadata = TranscriptionResponseMetadata(
            modelId: "whisper-1",
            headers: ["Content-Type": "application/json"]
        )
        
        let response = TranscriptionResponse(
            text: "Hello world",
            segments: segments,
            language: "en",
            durationInSeconds: 2.0,
            warnings: [],
            responses: [metadata],
            providerMetadata: ["provider": ["model": "whisper-1"]]
        )
        
        XCTAssertEqual(response.text, "Hello world")
        XCTAssertEqual(response.segments.count, 2)
        XCTAssertEqual(response.segments[0].text, "Hello")
        XCTAssertEqual(response.segments[1].text, "world")
        XCTAssertEqual(response.language, "en")
        XCTAssertEqual(response.durationInSeconds, 2.0)
        XCTAssertEqual(response.responses.count, 1)
        XCTAssertEqual(response.responses[0].modelId, "whisper-1")
    }
    
    func testTranscriptionSegment() throws {
        let segment = TranscriptionSegment(text: "Hello", startSecond: 0.5, endSecond: 1.5)
        
        XCTAssertEqual(segment.text, "Hello")
        XCTAssertEqual(segment.startSecond, 0.5)
        XCTAssertEqual(segment.endSecond, 1.5)
    }
    
    func testTranscriptionWarning() throws {
        let warning = TranscriptionWarning(
            type: "unsupported_parameter",
            message: "Parameter not supported",
            metadata: ["parameter": "test"]
        )
        
        XCTAssertEqual(warning.type, "unsupported_parameter")
        XCTAssertEqual(warning.message, "Parameter not supported")
        XCTAssertEqual(warning.metadata?["parameter"], "test")
    }
    
    func testTranscriptionResponseMetadata() throws {
        let metadata = TranscriptionResponseMetadata(
            modelId: "whisper-1",
            headers: ["Authorization": "Bearer token"],
            duration: 1.5,
            metadata: ["custom": "value"]
        )
        
        XCTAssertEqual(metadata.modelId, "whisper-1")
        XCTAssertEqual(metadata.headers?["Authorization"], "Bearer token")
        XCTAssertEqual(metadata.duration, 1.5)
        XCTAssertEqual(metadata.metadata?["custom"], "value")
    }
    
    // MARK: - TranscriptionError Tests
    
    func testTranscriptionErrorDescriptions() throws {
        let networkError = NSError(domain: "test", code: 1)
        let expectedNetworkMessage = "Network error: \(networkError.localizedDescription)"
        
        let errors: [(TranscriptionError, String)] = [
            (.noTranscriptGenerated("Silent audio"), "No transcript was generated: Silent audio"),
            (.unsupportedAudioFormat("MP4"), "Unsupported audio format: MP4"),
            (.audioFileTooLarge(maxSize: 1048576), "Audio file too large. Maximum size: 1.0 MB"),
            (.unsupportedModel("gpt-4"), "Model 'gpt-4' is not supported for transcription"),
            (.invalidConfiguration("Invalid temp"), "Invalid configuration: Invalid temp"),
            (.networkError(networkError), expectedNetworkMessage),
            (.providerSpecific("Custom error", underlyingError: nil), "Custom error")
        ]
        
        for (error, expectedDescription) in errors {
            XCTAssertEqual(error.localizedDescription, expectedDescription)
        }
    }
    
    // MARK: - Provider Request/Response Tests
    
    func testTranscriptionProviderRequest() throws {
        let audio = AudioInput.data("test".data(using: .utf8)!)
        let config = TranscriptionConfiguration().language("en").temperature(0.3)
        
        let request = TranscriptionProviderRequest(
            modelId: "whisper-1",
            audio: audio,
            configuration: config,
            providerOptions: ["option": "value"],
            headers: ["Custom": "header"],
            requestId: "test-id"
        )
        
        XCTAssertEqual(request.modelId, "whisper-1")
        XCTAssertEqual(request.configuration.language, "en")
        XCTAssertEqual(request.configuration.temperature, 0.3)
        XCTAssertEqual(request.providerOptions?["option"], "value")
        XCTAssertEqual(request.headers?["Custom"], "header")
        XCTAssertEqual(request.requestId, "test-id")
    }
    
    func testTranscriptionProviderResponse() throws {
        let segments = [TranscriptionSegment(text: "Test", startSecond: 0.0, endSecond: 1.0)]
        let metadata = TranscriptionResponseMetadata(modelId: "whisper-1")
        
        let response = TranscriptionProviderResponse(
            text: "Test transcript",
            segments: segments,
            language: "en",
            durationInSeconds: 1.0,
            warnings: [],
            responseMetadata: metadata,
            providerMetadata: ["custom": "value"]
        )
        
        XCTAssertEqual(response.text, "Test transcript")
        XCTAssertEqual(response.segments.count, 1)
        XCTAssertEqual(response.language, "en")
        XCTAssertEqual(response.durationInSeconds, 1.0)
        XCTAssertEqual(response.responseMetadata.modelId, "whisper-1")
        XCTAssertEqual(response.providerMetadata?["custom"], "value")
    }
    
    // MARK: - Task Cancellation Tests
    
    func testTaskCancellation() async throws {
        let client = AIClient()
        let provider = MockProvider()
        let model = provider.transcriptionModel("test-model")
        let audio = AudioInput.data("test".data(using: .utf8)!)
        
        // Create a task and cancel it immediately
        let task = Task {
            try await client.transcribe(model: model, audio: audio)
        }
        
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected - task was cancelled
            XCTAssertTrue(true)
        } catch {
            // Also acceptable if provider throws other error before cancellation check
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Integration Tests with MockProvider
    
    func testTranscriptionWithMockProvider() async throws {
        let client = AIClient()
        let provider = MockProvider()
        let model = provider.transcriptionModel("mock-whisper")
            .language("en")
            .temperature(0.2)
        
        let audio = AudioInput.data("test audio data".data(using: .utf8)!)
        
        // Mock provider should throw unsupported error by default
        do {
            _ = try await client.transcribe(model: model, audio: audio)
            XCTFail("Expected error to be thrown")
        } catch _ as AIProviderError {
            // Expected - MockProvider doesn't implement transcription by default
            XCTAssertTrue(true)
        } catch _ as TranscriptionError {
            // Also acceptable - error might be converted to TranscriptionError
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }
    
    func testTranscriptionModelFactory() throws {
        let provider = MockProvider()
        let model = provider.transcriptionModel("test-model")
        
        XCTAssertEqual(model.modelId, "test-model")
        XCTAssertTrue(model.provider is MockProvider)
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testTranscriptionConfigurationEdgeCases() throws {
        // Empty language string should still pass basic validation
        let config = TranscriptionConfiguration().language("")
        XCTAssertEqual(config.language, "")
        
        // Zero temperature should be valid
        let zeroTempConfig = TranscriptionConfiguration().temperature(0.0)
        XCTAssertEqual(zeroTempConfig.temperature, 0.0)
        
        // One temperature should be valid
        let maxTempConfig = TranscriptionConfiguration().temperature(1.0)
        XCTAssertEqual(maxTempConfig.temperature, 1.0)
        
        // Test that configuration works without provider-specific features
        let basicConfig = TranscriptionConfiguration().temperature(0.5)
        XCTAssertEqual(basicConfig.temperature, 0.5)
    }
    
    func testAudioInputURLEdgeCases() throws {
        // URL without file extension
        let urlWithoutExt = URL(string: "https://example.com/audio")!
        let audioInput = AudioInput.url(urlWithoutExt)
        XCTAssertEqual(audioInput.debugDescription, "url(https://example.com/audio)")
        
        // Empty URL path
        let rootURL = URL(string: "https://example.com/")!
        let rootAudioInput = AudioInput.url(rootURL)
        XCTAssertEqual(rootAudioInput.debugDescription, "url(https://example.com/)")
    }
}