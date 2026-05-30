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
}
