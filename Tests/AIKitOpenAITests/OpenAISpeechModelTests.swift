import XCTest
@testable import AIKitOpenAI
import AIKitProviders

final class OpenAISpeechModelTests: XCTestCase {
  func testSpeakSendsJSONBodyAndReturnsRawAudio() async throws {
    let audioBytes = Data([0x49, 0x44, 0x33, 0x04, 0x00])
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioSpeechURL: .init(type: .rawData(audioBytes))
    ])

    let model = server.speechModel("tts-1")
    let result = try await model.speak(
      .init(
        text: "Hello there",
        providerOptions: ["openai": [
          "voice": .string("nova"),
          "response_format": .string("mp3"),
          "speed": .number(1.25),
        ]]
      )
    )

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["model"], .string("tts-1"))
    XCTAssertEqual(body["input"], .string("Hello there"))
    XCTAssertEqual(body["voice"], .string("nova"))
    XCTAssertEqual(body["response_format"], .string("mp3"))
    XCTAssertEqual(body["speed"], .number(1.25))

    XCTAssertEqual(result.audio, audioBytes)
    XCTAssertEqual(result.modelID, "tts-1")
  }

  func testSpeakDefaultsVoiceToAlloy() async throws {
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioSpeechURL: .init(type: .rawData(Data([0x00])))
    ])

    let model = server.speechModel("tts-1")
    _ = try await model.speak(.init(text: "hi"))

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["voice"], .string("alloy"))
  }

  func testSpeakPassesInstructionsOption() async throws {
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioSpeechURL: .init(type: .rawData(Data([0x00])))
    ])

    let model = server.speechModel("gpt-4o-mini-tts")
    _ = try await model.speak(
      .init(
        text: "hi",
        providerOptions: ["openai": [
          "instructions": .string("speak cheerfully"),
        ]]
      )
    )

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["instructions"], .string("speak cheerfully"))
  }

  func testSpeakOmitsUnsetOptions() async throws {
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioSpeechURL: .init(type: .rawData(Data([0x00])))
    ])

    let model = server.speechModel("tts-1")
    _ = try await model.speak(.init(text: "hi"))

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertNil(body["response_format"])
    XCTAssertNil(body["speed"])
    XCTAssertNil(body["instructions"])
  }

  func testSpeakReturnsRawAudioForDifferentFormats() async throws {
    // The audio bytes are returned verbatim regardless of the requested format.
    let wavBytes = Data([0x52, 0x49, 0x46, 0x46])
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioSpeechURL: .init(type: .rawData(wavBytes))
    ])

    let model = server.speechModel("tts-1")
    let result = try await model.speak(
      .init(
        text: "hi",
        providerOptions: ["openai": ["response_format": .string("wav")]]
      )
    )

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["response_format"], .string("wav"))
    XCTAssertEqual(result.audio, wavBytes)
  }

  func testSpeakPassesConfigHeaders() async throws {
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioSpeechURL: .init(type: .rawData(Data([0x00])))
    ])

    let model = server.speechModel("tts-1")
    _ = try await model.speak(.init(text: "hi"))

    let headers = server.calls.first?.requestHeaders ?? [:]
    XCTAssertEqual(headers["authorization"], "Bearer test-api-key")
    XCTAssertEqual(headers["content-type"], "application/json")
  }
}
