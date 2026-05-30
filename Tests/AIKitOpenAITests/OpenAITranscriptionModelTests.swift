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
}
