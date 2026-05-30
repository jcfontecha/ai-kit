import XCTest
@testable import AIKitOpenAI
import AIKitProviders

final class OpenAIImageModelTests: XCTestCase {
  private func b64Response(_ values: [String]) -> JSONValue {
    .object([
      "created": .number(0),
      "data": .array(values.map { .object(["b64_json": .string($0)]) }),
    ])
  }

  func testMaxImagesPerCall() async {
    let server = OpenAITestServer(config: [:])
    let gptImage = await server.imageModel("gpt-image-1").maxImagesPerCall()
    let dalle3 = await server.imageModel("dall-e-3").maxImagesPerCall()
    let unknown = await server.imageModel("some-future-model").maxImagesPerCall()
    XCTAssertEqual(gptImage, 10)
    XCTAssertEqual(dalle3, 1)
    XCTAssertEqual(unknown, 1)
  }

  func testGenerateBuildsRequestBodyAndDecodesBase64() async throws {
    let pixel = Data([0xDE, 0xAD, 0xBE, 0xEF]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    let result = try await model.generate(
      .init(
        prompt: "a serene mountain",
        n: 2,
        size: "1024x1024",
        providerOptions: ["openai": [
          "quality": .string("high"),
          "output_format": .string("png"),
        ]]
      )
    )

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["model"], .string("gpt-image-1"))
    XCTAssertEqual(body["prompt"], .string("a serene mountain"))
    XCTAssertEqual(body["n"], .number(2))
    XCTAssertEqual(body["size"], .string("1024x1024"))
    XCTAssertEqual(body["response_format"], .string("b64_json"))
    XCTAssertEqual(body["quality"], .string("high"))
    XCTAssertEqual(body["output_format"], .string("png"))

    XCTAssertEqual(result.images.count, 1)
    XCTAssertEqual(result.images.first, .base64(pixel))
    XCTAssertEqual(result.response.modelID, "gpt-image-1")
    XCTAssertTrue(result.warnings.isEmpty)
  }

  func testAspectRatioEmitsWarning() async throws {
    let pixel = Data([0x01]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    let result = try await model.generate(.init(prompt: "x", aspectRatio: "16:9"))

    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertEqual(result.warnings.first?.code, "unsupported-setting")
  }

  func testImageEditUsesMultipart() async throws {
    let pixel = Data([0x02]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imageEditsURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    // ASCII bytes so the multipart body remains UTF-8 decodable for assertions.
    let inputImage = Data("PNGDATA".utf8)
    let result = try await model.generate(
      .init(
        prompt: "make it night",
        files: [.file(data: inputImage, mediaType: "image/png")]
      )
    )

    let call = try XCTUnwrap(server.calls.first)
    let contentType = call.requestHeaders["content-type"] ?? ""
    XCTAssertTrue(contentType.hasPrefix("multipart/form-data"), "Expected multipart, got \(contentType)")
    XCTAssertTrue(call.requestBody.contains("name=\"image\""))
    XCTAssertTrue(call.requestBody.contains("name=\"model\""))
    XCTAssertTrue(call.requestBody.contains("gpt-image-1"))
    XCTAssertTrue(call.requestBody.contains("make it night"))

    XCTAssertEqual(result.images.first, .base64(pixel))
  }
}
