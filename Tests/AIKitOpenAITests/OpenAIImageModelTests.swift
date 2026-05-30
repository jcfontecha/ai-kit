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

  func testGeneratePassesCustomHeaders() async throws {
    let pixel = Data([0x03]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    _ = try await model.generate(
      .init(prompt: "x", headers: ["X-Custom-Header": "custom-value"])
    )

    let headers = server.calls.first?.requestHeaders ?? [:]
    XCTAssertEqual(headers["x-custom-header"], "custom-value")
    XCTAssertEqual(headers["authorization"], "Bearer test-api-key")
    XCTAssertEqual(headers["content-type"], "application/json")
  }

  func testGenerateMapsProviderOptionsIntoBody() async throws {
    let pixel = Data([0x04]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    _ = try await model.generate(
      .init(
        prompt: "x",
        providerOptions: ["openai": [
          "quality": .string("high"),
          "background": .string("transparent"),
          "output_format": .string("webp"),
          "moderation": .string("low"),
          "style": .string("vivid"),
          "user": .string("img-user"),
        ]]
      )
    )

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["quality"], .string("high"))
    XCTAssertEqual(body["background"], .string("transparent"))
    XCTAssertEqual(body["output_format"], .string("webp"))
    XCTAssertEqual(body["moderation"], .string("low"))
    XCTAssertEqual(body["style"], .string("vivid"))
    XCTAssertEqual(body["user"], .string("img-user"))
  }

  func testGenerateDropsNullAndUnknownProviderOptions() async throws {
    let pixel = Data([0x05]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    _ = try await model.generate(
      .init(
        prompt: "x",
        providerOptions: ["openai": [
          "quality": .null,
          "unsupported": .string("nope"),
        ]]
      )
    )

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertNil(body["quality"])
    XCTAssertNil(body["unsupported"])
  }

  func testGenerateSendsResponseFormatForDallE3() async throws {
    let pixel = Data([0x06]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("dall-e-3")
    let result = try await model.generate(.init(prompt: "a cat", n: 1))

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["model"], .string("dall-e-3"))
    XCTAssertEqual(body["response_format"], .string("b64_json"))
    XCTAssertEqual(result.response.modelID, "dall-e-3")
  }

  func testGenerateMultipleImagesDecodesAll() async throws {
    let a = Data([0xAA]).base64EncodedString()
    let b = Data([0xBB]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([a, b])))
    ])

    let model = server.imageModel("gpt-image-1")
    let result = try await model.generate(.init(prompt: "x", n: 2))

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected JSON body")
    }
    XCTAssertEqual(body["n"], .number(2))
    XCTAssertEqual(result.images.count, 2)
    XCTAssertEqual(result.images[0], .base64(a))
    XCTAssertEqual(result.images[1], .base64(b))
  }

  func testGenerateIgnoresAbsentRevisedPrompt() async throws {
    // Response carries no `revised_prompt`; decoding must still succeed.
    let pixel = Data([0x07]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    let result = try await model.generate(.init(prompt: "x"))

    XCTAssertEqual(result.images.first, .base64(pixel))
  }

  func testGenerateExposesUsageInProviderMetadata() async throws {
    let pixel = Data([0x08]).base64EncodedString()
    let response = JSONValue.object([
      "created": .number(0),
      "data": .array([.object(["b64_json": .string(pixel)])]),
      "usage": .object([
        "total_tokens": .number(100),
        "input_tokens": .number(60),
        "output_tokens": .number(40),
      ]),
    ])
    let server = OpenAITestServer(config: [
      OpenAITestServer.imagesURL: .init(type: .jsonValue(response))
    ])

    let model = server.imageModel("gpt-image-1")
    let result = try await model.generate(.init(prompt: "x"))

    guard case let .object(metadata)? = result.providerMetadata?["openai"],
          case let .object(usage)? = metadata["usage"] else {
      return XCTFail("Expected usage in provider metadata")
    }
    XCTAssertEqual(usage["total_tokens"], .number(100))
    XCTAssertEqual(usage["input_tokens"], .number(60))
    XCTAssertEqual(usage["output_tokens"], .number(40))
  }

  func testImageEditWithRawBytesInput() async throws {
    let pixel = Data([0x09]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imageEditsURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    let inputImage = Data("RAWBYTES".utf8)
    let result = try await model.generate(
      .init(
        prompt: "edit it",
        files: [.file(data: inputImage, mediaType: "image/png")]
      )
    )

    let call = try XCTUnwrap(server.calls.first)
    // A single input image uses the `image` field (not the `image[]` array form).
    XCTAssertTrue(call.requestBody.contains("name=\"image\""))
    XCTAssertFalse(call.requestBody.contains("name=\"image[]\""))
    XCTAssertTrue(call.requestBody.contains("Content-Type: image/png"))
    XCTAssertTrue(call.requestBody.contains("RAWBYTES"))
    XCTAssertEqual(result.images.first, .base64(pixel))
  }

  func testImageEditWithMultipleImagesUsesArrayField() async throws {
    let pixel = Data([0x0A]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imageEditsURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    let result = try await model.generate(
      .init(
        prompt: "merge",
        files: [
          .file(data: Data("FIRST".utf8), mediaType: "image/png"),
          .file(data: Data("SECOND".utf8), mediaType: "image/png"),
        ]
      )
    )

    let call = try XCTUnwrap(server.calls.first)
    // Multiple input images switch to the repeated `image[]` field.
    XCTAssertTrue(call.requestBody.contains("name=\"image[]\""))
    XCTAssertTrue(call.requestBody.contains("FIRST"))
    XCTAssertTrue(call.requestBody.contains("SECOND"))
    XCTAssertEqual(result.images.first, .base64(pixel))
  }

  func testImageEditPutsProviderOptionsInFormData() async throws {
    let pixel = Data([0x0B]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imageEditsURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    _ = try await model.generate(
      .init(
        prompt: "edit",
        files: [.file(data: Data("IMG".utf8), mediaType: "image/png")],
        size: "1024x1024",
        providerOptions: ["openai": [
          "quality": .string("high"),
          "background": .string("opaque"),
        ]]
      )
    )

    let call = try XCTUnwrap(server.calls.first)
    XCTAssertTrue(call.requestBody.contains("name=\"size\""))
    XCTAssertTrue(call.requestBody.contains("1024x1024"))
    XCTAssertTrue(call.requestBody.contains("name=\"quality\""))
    XCTAssertTrue(call.requestBody.contains("high"))
    XCTAssertTrue(call.requestBody.contains("name=\"background\""))
    XCTAssertTrue(call.requestBody.contains("opaque"))
  }

  func testImageEditWithMaskUsesEditsEndpoint() async throws {
    let pixel = Data([0x0C]).base64EncodedString()
    let server = OpenAITestServer(config: [
      OpenAITestServer.imageEditsURL: .init(type: .jsonValue(b64Response([pixel])))
    ])

    let model = server.imageModel("gpt-image-1")
    let result = try await model.generate(
      .init(
        prompt: "mask edit",
        files: [.file(data: Data("IMG".utf8), mediaType: "image/png")],
        mask: .file(data: Data("MASK".utf8), mediaType: "image/png")
      )
    )

    let call = try XCTUnwrap(server.calls.first)
    XCTAssertTrue(call.requestBody.contains("name=\"mask\""))
    XCTAssertTrue(call.requestBody.contains("MASK"))
    XCTAssertEqual(result.images.first, .base64(pixel))
  }

  func testImageEditRejectsURLInput() async throws {
    let server = OpenAITestServer(config: [
      OpenAITestServer.imageEditsURL: .init(type: .jsonValue(b64Response([])))
    ])

    let model = server.imageModel("gpt-image-1")
    do {
      _ = try await model.generate(
        .init(
          prompt: "edit",
          files: [.url(URL(string: "https://example.com/image.png")!)]
        )
      )
      XCTFail("Expected URL-based image input to throw")
    } catch is OpenAIUnsupportedFunctionalityError {
      // expected
    }
  }
}
