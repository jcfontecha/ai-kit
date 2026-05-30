import XCTest
@testable import AIKitOpenAI
import AIKitProviders

final class OpenAITranscriptionModelTests: XCTestCase {
  func testTranscribeSendsMultipartAndDecodesText() async throws {
    let response = JSONValue.object(["text": .string("hello world")])
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioTranscriptionsURL: .init(type: .jsonValue(response))
    ])

    let model = server.transcriptionModel("whisper-1")
    let audio = Data([0x10, 0x20, 0x30])
    let result = try await model.transcribe(
      .init(
        audio: audio,
        mediaType: "audio/wav",
        providerOptions: ["openai": ["language": .string("en")]]
      )
    )

    let call = try XCTUnwrap(server.calls.first)
    let contentType = call.requestHeaders["content-type"] ?? ""
    XCTAssertTrue(contentType.hasPrefix("multipart/form-data"), "Expected multipart, got \(contentType)")
    XCTAssertTrue(call.requestBody.contains("name=\"file\""))
    XCTAssertTrue(call.requestBody.contains("name=\"model\""))
    XCTAssertTrue(call.requestBody.contains("whisper-1"))
    XCTAssertTrue(call.requestBody.contains("name=\"language\""))
    XCTAssertTrue(call.requestBody.contains("en"))

    XCTAssertEqual(result.text, "hello world")
    XCTAssertEqual(result.modelID, "whisper-1")
  }

  func testTranscribePassesAllProviderOptionsIntoMultipart() async throws {
    let response = JSONValue.object(["text": .string("ok")])
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioTranscriptionsURL: .init(type: .jsonValue(response))
    ])

    let model = server.transcriptionModel("whisper-1")
    _ = try await model.transcribe(
      .init(
        audio: Data([0x01]),
        mediaType: "audio/wav",
        providerOptions: ["openai": [
          "language": .string("es"),
          "prompt": .string("hint text"),
          "response_format": .string("verbose_json"),
          "temperature": .number(0.2),
        ]]
      )
    )

    let call = try XCTUnwrap(server.calls.first)
    XCTAssertTrue(call.requestBody.contains("name=\"language\""))
    XCTAssertTrue(call.requestBody.contains("es"))
    XCTAssertTrue(call.requestBody.contains("name=\"prompt\""))
    XCTAssertTrue(call.requestBody.contains("hint text"))
    XCTAssertTrue(call.requestBody.contains("name=\"response_format\""))
    XCTAssertTrue(call.requestBody.contains("verbose_json"))
    XCTAssertTrue(call.requestBody.contains("name=\"temperature\""))
    XCTAssertTrue(call.requestBody.contains("0.2"))
  }

  func testTranscribeFileCarriesContentTypeFromMediaType() async throws {
    let response = JSONValue.object(["text": .string("ok")])
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioTranscriptionsURL: .init(type: .jsonValue(response))
    ])

    let model = server.transcriptionModel("whisper-1")
    _ = try await model.transcribe(.init(audio: Data([0x01]), mediaType: "audio/mpeg"))

    let call = try XCTUnwrap(server.calls.first)
    // The file part's Content-Type mirrors the request mediaType and the filename
    // extension is derived from it.
    XCTAssertTrue(call.requestBody.contains("Content-Type: audio/mpeg"))
    XCTAssertTrue(call.requestBody.contains("filename=\"audio.mp3\""))
  }

  func testTranscribeDefaultsMediaTypeToWav() async throws {
    let response = JSONValue.object(["text": .string("ok")])
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioTranscriptionsURL: .init(type: .jsonValue(response))
    ])

    let model = server.transcriptionModel("whisper-1")
    _ = try await model.transcribe(.init(audio: Data([0x01])))

    let call = try XCTUnwrap(server.calls.first)
    XCTAssertTrue(call.requestBody.contains("Content-Type: audio/wav"))
    XCTAssertTrue(call.requestBody.contains("filename=\"audio.wav\""))
  }

  func testTranscribeHandlesTextOnlyResponse() async throws {
    // Minimal response with only `text` (no words/segments/language/duration).
    let response = JSONValue.object(["text": .string("just text")])
    let server = OpenAITestServer(config: [
      OpenAITestServer.audioTranscriptionsURL: .init(type: .jsonValue(response))
    ])

    let model = server.transcriptionModel("whisper-1")
    let result = try await model.transcribe(.init(audio: Data([0x01]), mediaType: "audio/wav"))

    XCTAssertEqual(result.text, "just text")
    XCTAssertEqual(result.modelID, "whisper-1")
  }
}
