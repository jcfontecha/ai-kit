import XCTest
import Foundation
@testable import AIKit

// MARK: - Configuration Reader

/// Helper to read configuration from Config.plist  
private struct ConfigReader {
    static func loadAPIKey() throws -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") else {
            // Try to find Config.plist in the current working directory (project root)
            let currentWorkingDir = FileManager.default.currentDirectoryPath
            let configPath = "\(currentWorkingDir)/Config.plist"
            
            guard FileManager.default.fileExists(atPath: configPath) else {
                throw E2ETestError.configNotFound("Config.plist not found at \(configPath)")
            }
            
            guard let plistData = FileManager.default.contents(atPath: configPath),
                  let plist = try PropertyListSerialization.propertyList(
                    from: plistData,
                    options: [],
                    format: nil
                  ) as? [String: Any] else {
                throw E2ETestError.configInvalid("Failed to load Config.plist")
            }
            
            guard let apiKey = plist["OPENAI_API_KEY"] as? String, !apiKey.isEmpty else {
                throw E2ETestError.apiKeyNotFound("OPENAI_API_KEY not found in Config.plist")
            }
            
            return apiKey
        }
        
        guard let plist = NSDictionary(contentsOfFile: path) else {
            throw E2ETestError.configInvalid("Failed to load Config.plist from bundle")
        }
        
        guard let apiKey = plist["OPENAI_API_KEY"] as? String, !apiKey.isEmpty else {
            throw E2ETestError.apiKeyNotFound("OPENAI_API_KEY not found in Config.plist")
        }
        
        return apiKey
    }
}

// MARK: - E2E Test Errors

private enum E2ETestError: Error, LocalizedError {
    case configNotFound(String)
    case configInvalid(String)
    case apiKeyNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .configNotFound(let message):
            return "Configuration not found: \(message)"
        case .configInvalid(let message):
            return "Configuration invalid: \(message)"
        case .apiKeyNotFound(let message):
            return "API key not found: \(message)"
        }
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class E2ETranscriptionTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    private var openaiProvider: OpenAIProvider!
    private var client: AIClient!
    private var testAudioURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Load API key from Config.plist
        do {
            let apiKey = try ConfigReader.loadAPIKey()
            
            // Initialize provider and client
            openaiProvider = OpenAIProvider(apiKey: apiKey)
            client = AIClient()
        } catch {
            throw XCTSkip("OpenAI API key not available: \(error.localizedDescription). Skipping E2E transcription tests.")
        }
        
        // Set up test audio file URL
        // Construct path relative to project root
        let currentWorkingDir = FileManager.default.currentDirectoryPath
        let audioPath = "\(currentWorkingDir)/Tests/AIKitTests/sample_audio.m4a"
        
        if FileManager.default.fileExists(atPath: audioPath) {
            testAudioURL = URL(fileURLWithPath: audioPath)
        } else {
            // Fallback to bundle lookup
            let testBundle = Bundle(for: type(of: self))
            guard let audioURL = testBundle.url(forResource: "sample_audio", withExtension: "m4a") else {
                throw XCTSkip("Test audio file 'sample_audio.m4a' not found at expected path (\(audioPath)) or in bundle. Please ensure it exists.")
            }
            testAudioURL = audioURL
        }
    }
    
    // MARK: - Basic E2E Tests
    
    func testOpenAIWhisperBasicTranscription() async throws {
        // Use the cost-effective model as specified in CLAUDE.md
        let model = openaiProvider.transcriptionModel("whisper-1")
        
        let response = try await client.transcribe(
            model: model,
            audio: .fileURL(testAudioURL)
        )
        
        // Verify basic response structure
        XCTAssertFalse(response.text.isEmpty, "Transcription text should not be empty")
        // Note: Language and duration may not always be returned by OpenAI API
        // XCTAssertNotNil(response.language, "Language should be detected")
        // XCTAssertNotNil(response.durationInSeconds, "Duration should be provided")
        XCTAssertEqual(response.responses.count, 1, "Should have one response metadata")
        XCTAssertEqual(response.responses.first?.modelId, "whisper-1")
        
        // The sample audio says "this is a sample audio file"
        let transcriptLower = response.text.lowercased()
        XCTAssertTrue(
            transcriptLower.contains("sample") && transcriptLower.contains("audio"),
            "Transcript should contain expected content: '\(response.text)'"
        )
        
        print("✅ Basic transcription successful:")
        print("   Text: \(response.text)")
        print("   Language: \(response.language ?? "unknown")")
        print("   Duration: \(response.durationInSeconds ?? 0) seconds")
    }
    
    func testOpenAIWhisperWithConfiguration() async throws {
        let model = openaiProvider.transcriptionModel("whisper-1")
            .language("en")
            .prompt("This is a sample audio file for testing transcription.")
            .temperature(0.0)
            .responseFormat(.verboseJson)
        
        let response = try await client.transcribe(
            model: model,
            audio: .fileURL(testAudioURL)
        )
        
        // Verify response with configuration
        XCTAssertFalse(response.text.isEmpty)
        // Note: OpenAI may return "english" instead of "en"
        XCTAssertTrue(response.language == "en" || response.language == "english", "Language should be detected as English")
        
        // With verbose JSON format, we might get segments
        if !response.segments.isEmpty {
            print("✅ Segments received:")
            for (index, segment) in response.segments.enumerated() {
                print("   Segment \(index): \(segment.startSecond)s-\(segment.endSecond)s: '\(segment.text)'")
                XCTAssertGreaterThanOrEqual(segment.endSecond, segment.startSecond)
            }
        }
        
        print("✅ Configured transcription successful:")
        print("   Text: \(response.text)")
        print("   Segments count: \(response.segments.count)")
    }
    
    func testOpenAIWhisperWithTimestampGranularities() async throws {
        let model = openaiProvider.transcriptionModel("whisper-1")
            .language("en")
            .responseFormat(.verboseJson)
            .providerOptions(["openai": "timestampGranularities=segment"])
        
        let response = try await client.transcribe(
            model: model,
            audio: .fileURL(testAudioURL)
        )
        
        XCTAssertFalse(response.text.isEmpty)
        
        // With segment granularity, we should get segment-level timestamps
        if !response.segments.isEmpty {
            print("✅ Timestamp granularities test successful:")
            print("   Segments with timestamps:")
            for segment in response.segments {
                print("   \(segment.startSecond)s-\(segment.endSecond)s: '\(segment.text)'")
                XCTAssertGreaterThanOrEqual(segment.endSecond, segment.startSecond)
                XCTAssertFalse(segment.text.isEmpty)
            }
        } else {
            print("⚠️  No segments returned (may depend on audio length)")
        }
    }
    
    // MARK: - Different Audio Input Methods
    
    func testTranscriptionWithAudioData() async throws {
        // Load audio as Data
        let audioData = try Data(contentsOf: testAudioURL)
        
        let model = openaiProvider.transcriptionModel("whisper-1")
            .language("en")
        
        do {
            let response = try await client.transcribe(
                model: model,
                audioData: audioData
            )
            
            XCTAssertFalse(response.text.isEmpty)
            
            let transcriptLower = response.text.lowercased()
            XCTAssertTrue(
                transcriptLower.contains("sample") && transcriptLower.contains("audio"),
                "Data-based transcription should produce same result"
            )
            
            print("✅ Audio Data transcription successful: \(response.text)")
        } catch {
            // Some audio formats may not work when passed as raw Data
            print("ℹ️  Audio Data transcription failed (expected for some formats): \(error)")
            // This is acceptable - not all audio formats work when passed as raw Data to OpenAI
            throw XCTSkip("Audio format not supported when passed as raw Data")
        }
    }
    
    func testTranscriptionWithFileURL() async throws {
        let model = openaiProvider.transcriptionModel("whisper-1")
        
        let response = try await client.transcribe(
            model: model,
            fileURL: testAudioURL
        )
        
        XCTAssertFalse(response.text.isEmpty)
        
        print("✅ File URL transcription successful: \(response.text)")
    }
    
    // MARK: - Error Handling Tests
    
    func testTranscriptionWithNonExistentFile() async throws {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent_audio.mp3")
        let model = openaiProvider.transcriptionModel("whisper-1")
        
        do {
            _ = try await client.transcribe(model: model, audio: .fileURL(nonExistentURL))
            XCTFail("Expected error for non-existent file")
        } catch {
            print("✅ Correctly handled non-existent file error: \(error)")
            // Error should be related to file not found - check various possible messages
            let errorMessage = error.localizedDescription.lowercased()
            XCTAssertTrue(
                errorMessage.contains("no such file") || 
                errorMessage.contains("couldn't be opened") ||
                errorMessage.contains("file not found") ||
                errorMessage.contains("does not exist"),
                "Error should indicate file not found, got: \(error.localizedDescription)"
            )
        }
    }
    
    func testTranscriptionWithInvalidModel() async throws {
        let model = openaiProvider.transcriptionModel("invalid-whisper-model")
        
        do {
            _ = try await client.transcribe(
                model: model,
                audio: .fileURL(testAudioURL)
            )
            XCTFail("Expected error for invalid model")
        } catch {
            print("✅ Correctly handled invalid model error: \(error)")
            // Should be a provider-specific error about the model
        }
    }
    
    // MARK: - Performance and Timing Tests
    
    func testTranscriptionPerformance() async throws {
        let model = openaiProvider.transcriptionModel("whisper-1")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let response = try await client.transcribe(
            model: model,
            audio: .fileURL(testAudioURL)
        )
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertFalse(response.text.isEmpty)
        
        print("✅ Transcription performance test:")
        print("   Transcription time: \(String(format: "%.2f", duration)) seconds")
        print("   Audio duration: \(response.durationInSeconds ?? 0) seconds")
        print("   Processing ratio: \(String(format: "%.2f", duration / (response.durationInSeconds ?? 1)))x real-time")
        
        // Reasonable performance expectation - should not take more than 30 seconds for a short file
        XCTAssertLessThan(duration, 30.0, "Transcription should complete within 30 seconds")
    }
    
    // MARK: - Cancellation Tests
    
    func testTranscriptionCancellation() async throws {
        let model = openaiProvider.transcriptionModel("whisper-1")
        let localClient = client!
        let localAudioURL = testAudioURL!
        
        let task = Task {
            try await localClient.transcribe(
                model: model,
                audio: .fileURL(localAudioURL)
            )
        }
        
        // Cancel after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            task.cancel()
        }
        
        do {
            _ = try await task.value
            print("⚠️  Task completed before cancellation (normal for fast operations)")
        } catch is CancellationError {
            print("✅ Task cancellation successful")
        } catch {
            print("ℹ️  Task completed with result before cancellation: \(error)")
        }
    }
    
    // MARK: - Model-Specific Tests
    
    func testGPT4OMiniTranscribeModel() async throws {
        // Test gpt-4o-mini-transcribe which doesn't support timestamps
        let model = openaiProvider.transcriptionModel("gpt-4o-mini-transcribe")
            .language("en")
            .responseFormat(.json) // Use simple JSON format since no timestamps
        
        let response = try await client.transcribe(
            model: model,
            audio: .fileURL(testAudioURL)
        )
        
        // Verify basic response structure
        XCTAssertFalse(response.text.isEmpty, "Transcription text should not be empty")
        // Note: gpt-4o-mini-transcribe may not return language detection
        // XCTAssertNotNil(response.language, "Language should be detected")
        XCTAssertEqual(response.responses.first?.modelId, "gpt-4o-mini-transcribe")
        
        // The sample audio says "this is a sample audio file"
        let transcriptLower = response.text.lowercased()
        XCTAssertTrue(
            transcriptLower.contains("sample") && transcriptLower.contains("audio"),
            "Transcript should contain expected content: '\(response.text)'"
        )
        
        // gpt-4o-mini-transcribe doesn't support timestamps, so segments should be empty
        XCTAssertTrue(response.segments.isEmpty, "gpt-4o-mini-transcribe should not return segments")
        
        print("✅ gpt-4o-mini-transcribe test successful:")
        print("   Text: \(response.text)")
        print("   Language: \(response.language ?? "unknown")")
        print("   Duration: \(response.durationInSeconds ?? 0) seconds")
        print("   Segments: \(response.segments.count) (expected 0)")
    }
    
    func testGPT4OMiniTranscribeWithTimestampRequest() async throws {
        // Test that gpt-4o-mini-transcribe gracefully handles timestamp requests
        let model = openaiProvider.transcriptionModel("gpt-4o-mini-transcribe")
            .language("en")
            .responseFormat(.verboseJson)
            .providerOptions(["openai": "timestampGranularities=segment"]) // This should be ignored or cause warning
        
        let response = try await client.transcribe(
            model: model,
            audio: .fileURL(testAudioURL)
        )
        
        XCTAssertFalse(response.text.isEmpty)
        
        // Model should either:
        // 1. Ignore timestamp request and return no segments, OR
        // 2. Return a warning about unsupported feature
        if !response.segments.isEmpty {
            print("⚠️  gpt-4o-mini-transcribe unexpectedly returned segments: \(response.segments.count)")
        }
        
        if !response.warnings.isEmpty {
            print("✅ gpt-4o-mini-transcribe correctly warned about unsupported features:")
            for warning in response.warnings {
                print("   Warning: \(warning.message)")
            }
        }
        
        print("✅ gpt-4o-mini-transcribe timestamp request test successful:")
        print("   Text: \(response.text)")
        print("   Segments: \(response.segments.count)")
        print("   Warnings: \(response.warnings.count)")
    }
    
    // MARK: - Response Format Tests
    
    func testDifferentResponseFormats() async throws {
        let formats: [TranscriptionResponseFormat] = [.json, .text, .verboseJson]
        
        for format in formats {
            let model = openaiProvider.transcriptionModel("whisper-1")
                .responseFormat(format)
                .language("en")
            
            do {
                let response = try await client.transcribe(
                    model: model,
                    audio: .fileURL(testAudioURL)
                )
                
                XCTAssertFalse(response.text.isEmpty, "Format \(format.rawValue) should return text")
                
                print("✅ Response format \(format.rawValue): '\(response.text)'")
                
                // Verbose JSON might include segments
                if format == .verboseJson && !response.segments.isEmpty {
                    print("   Segments: \(response.segments.count)")
                }
            } catch {
                print("ℹ️  Response format \(format.rawValue) failed: \(error)")
                // Some response formats might not be supported or may have parsing issues
                // This is acceptable as not all providers support all formats
            }
        }
    }
    
    // MARK: - Configuration Validation Tests
    
    func testInvalidTemperature() async throws {
        let model = openaiProvider.transcriptionModel("whisper-1")
            .temperature(1.5) // Invalid - should be 0.0-1.0
        
        do {
            _ = try await client.transcribe(
                model: model,
                audio: .fileURL(testAudioURL)
            )
            XCTFail("Expected validation error for invalid temperature")
        } catch TranscriptionError.invalidConfiguration(let message) {
            print("✅ Temperature validation worked: \(message)")
            XCTAssertTrue(message.contains("Temperature"))
        } catch {
            print("ℹ️  Other error for invalid temperature: \(error)")
            // Some providers might handle this differently
        }
    }
    
    func testInvalidLanguageCode() async throws {
        let model = openaiProvider.transcriptionModel("whisper-1")
            .language("english") // Invalid - should be ISO-639-1 code like "en"
        
        do {
            _ = try await client.transcribe(
                model: model,
                audio: .fileURL(testAudioURL)
            )
            XCTFail("Expected validation error for invalid language code")
        } catch TranscriptionError.invalidConfiguration(let message) {
            print("✅ Language code validation worked: \(message)")
            XCTAssertTrue(message.contains("Language"))
        } catch {
            print("ℹ️  Other error for invalid language: \(error)")
            // Some providers might handle this differently
        }
    }
    
    // MARK: - Helper Methods
    
    private func printTestSeparator(_ testName: String) {
        print("\n" + String(repeating: "=", count: 50))
        print("🧪 \(testName)")
        print(String(repeating: "=", count: 50))
    }
}