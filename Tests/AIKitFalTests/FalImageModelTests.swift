import Foundation
import XCTest
import AIKitProviders
@testable import AIKitFal

final class FalImageModelTests: XCTestCase {
  private let prompt = "A cute baby sea otter"

  private func makeServerWithDefaultResponses() throws -> FalTestServer {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "images": .array([
            .object([
              "url": .string("https://api.example.com/image.png"),
              "width": .number(1024),
              "height": .number(1024),
              "content_type": .string("image/png"),
            ]),
          ]),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)
    return server
  }

  private func createBasicModel(
    server: FalTestServer,
    headers: [String: String]? = nil,
    currentDate: (@Sendable () -> Date)? = nil
  ) -> FalImageModel {
    FalImageModel(
      modelId: "fal-ai/qwen-image",
      config: FalImageModelConfig(
        baseURL: "https://api.example.com",
        apiKey: nil,
        headers: { headers ?? ["api-key": "test-key"] },
        transport: server.transport(),
        currentDate: currentDate ?? { @Sendable in Date() }
      )
    )
  }

  func testDoGenerate_passesCorrectParametersIncludingSize() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)

    _ = try await model.generate(
      .init(
        prompt: prompt,
        n: 1,
        size: "1024x1024",
        seed: 123,
        providerOptions: ["fal": ["additional_param": .string("value")]]
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string(prompt),
        "seed": .number(123),
        "image_size": .object([
          "width": .number(1024),
          "height": .number(1024),
        ]),
        "num_images": .number(1),
        "additional_param": .string("value"),
      ])
    )
  }

  func testDoGenerate_convertsCamelCaseProviderOptionsToSnakeCase() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)

    let result = try await model.generate(
      .init(
        prompt: prompt,
        n: 1,
        providerOptions: [
          "fal": [
            "imageUrl": .string("https://example.com/image.png"),
            "guidanceScale": .number(7.5),
            "numInferenceSteps": .number(50),
            "enableSafetyChecker": .bool(false),
          ],
        ]
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string(prompt),
        "num_images": .number(1),
        "image_url": .string("https://example.com/image.png"),
        "guidance_scale": .number(7.5),
        "num_inference_steps": .number(50),
        "enable_safety_checker": .bool(false),
      ])
    )

    XCTAssertEqual(result.warnings.count, 0)
  }

  func testDoGenerate_acceptsDeprecatedSnakeCaseProviderOptionsWithWarning() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)

    let result = try await model.generate(
      .init(
        prompt: prompt,
        n: 1,
        providerOptions: [
          "fal": [
            "image_url": .string("https://example.com/image.png"),
            "guidance_scale": .number(7.5),
            "num_inference_steps": .number(50),
          ],
        ]
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string(prompt),
        "num_images": .number(1),
        "image_url": .string("https://example.com/image.png"),
        "guidance_scale": .number(7.5),
        "num_inference_steps": .number(50),
      ])
    )

    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertEqual(result.warnings.first?.code, "other")
    XCTAssertTrue(result.warnings.first?.message.contains("deprecated snake_case") == true)
    XCTAssertTrue(result.warnings.first?.message.contains("'image_url' (use 'imageUrl')") == true)
    XCTAssertTrue(result.warnings.first?.message.contains("'guidance_scale' (use 'guidanceScale')") == true)
    XCTAssertTrue(result.warnings.first?.message.contains("'num_inference_steps' (use 'numInferenceSteps')") == true)
  }

  func testDoGenerate_convertsAspectRatioToSize() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)

    _ = try await model.generate(.init(prompt: prompt, n: 1, aspectRatio: "16:9"))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string(prompt),
        "image_size": .string("landscape_16_9"),
        "num_images": .number(1),
      ])
    )
  }

  func testDoGenerate_passesHeaders() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server, headers: ["Custom-Provider-Header": "provider-header-value"])

    _ = try await model.generate(
      .init(
        prompt: prompt,
        n: 1,
        providerOptions: [:],
        headers: ["Custom-Request-Header": "request-header-value"]
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestHeaders,
      [
        "content-type": "application/json",
        "custom-provider-header": "provider-header-value",
        "custom-request-header": "request-header-value",
      ]
    )
  }

  func testDoGenerate_handlesAPIValidationErrors() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "detail": .array([
            .object([
              "loc": .array([.string("prompt")]),
              "msg": .string("Invalid prompt"),
              "type": .string("value_error"),
            ]),
          ]),
        ])
      ),
      status: 400
    )

    let model = createBasicModel(server: server)
    do {
      _ = try await model.generate(.init(prompt: prompt, n: 1))
      XCTFail("Expected error")
    } catch {
      let apiError = error as? FalAPIError
      XCTAssertEqual(apiError?.message, "prompt: Invalid prompt")
      XCTAssertEqual(apiError?.statusCode, 400)
      XCTAssertEqual(apiError?.url, "https://api.example.com/fal-ai/qwen-image")
    }
  }

  func testResponseMetadata_includesTimestampHeadersAndModelId() async throws {
    let server = try makeServerWithDefaultResponses()
    let testDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z
    let model = createBasicModel(server: server, currentDate: { testDate })

    let result = try await model.generate(.init(prompt: prompt, n: 1))
    XCTAssertEqual(result.response.timestamp, testDate)
    XCTAssertEqual(result.response.modelID, "fal-ai/qwen-image")
    XCTAssertNotNil(result.response.headers)
  }

  func testProviderMetadata_forLora() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "images": .array([
            .object([
              "url": .string("https://api.example.com/image.png"),
              "width": .number(1024),
              "height": .number(1024),
              "content_type": .string("image/png"),
              "file_data": .string("<image file_data>"),
              "file_size": .number(123),
              "file_name": .string("<image file_name>"),
            ]),
          ]),
          "prompt": .string("<prompt>"),
          "seed": .number(123),
          "has_nsfw_concepts": .array([.bool(true)]),
          "debug_latents": .object([
            "url": .string("<debug_latents url>"),
            "content_type": .string("<debug_latents content_type>"),
            "file_name": .string("<debug_latents file_name>"),
            "file_data": .string("<debug_latents file_data>"),
            "file_size": .number(123),
          ]),
          "debug_per_pass_latents": .object([
            "url": .string("<debug_per_pass_latents url>"),
            "content_type": .string("<debug_per_pass_latents content_type>"),
            "file_name": .string("<debug_per_pass_latents file_name>"),
            "file_data": .string("<debug_per_pass_latents file_data>"),
            "file_size": .number(456),
          ]),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)

    let model = createBasicModel(server: server)
    let result = try await model.generate(.init(prompt: prompt, n: 1))

    XCTAssertEqual(
      result.providerMetadata,
      [
        "fal": .object([
          "images": .array([
            .object([
              "width": .number(1024),
              "height": .number(1024),
              "contentType": .string("image/png"),
              "fileName": .string("<image file_name>"),
              "fileData": .string("<image file_data>"),
              "fileSize": .number(123),
              "nsfw": .bool(true),
            ]),
          ]),
          "seed": .number(123),
          "debug_latents": .object([
            "url": .string("<debug_latents url>"),
            "content_type": .string("<debug_latents content_type>"),
            "file_name": .string("<debug_latents file_name>"),
            "file_data": .string("<debug_latents file_data>"),
            "file_size": .number(123),
          ]),
          "debug_per_pass_latents": .object([
            "url": .string("<debug_per_pass_latents url>"),
            "content_type": .string("<debug_per_pass_latents content_type>"),
            "file_name": .string("<debug_per_pass_latents file_name>"),
            "file_data": .string("<debug_per_pass_latents file_data>"),
            "file_size": .number(456),
          ]),
        ]),
      ]
    )
  }

  func testProviderMetadata_forLcm() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "images": .array([
            .object([
              "url": .string("https://api.example.com/image.png"),
              "width": .number(1024),
              "height": .number(1024),
            ]),
          ]),
          "seed": .number(123),
          "num_inference_steps": .number(456),
          "nsfw_content_detected": .array([.bool(false)]),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)

    let model = createBasicModel(server: server)
    let result = try await model.generate(.init(prompt: prompt, n: 1))

    XCTAssertEqual(
      result.providerMetadata,
      [
        "fal": .object([
          "images": .array([
            .object([
              "width": .number(1024),
              "height": .number(1024),
              "nsfw": .bool(false),
            ]),
          ]),
          "seed": .number(123),
          "num_inference_steps": .number(456),
        ]),
      ]
    )
  }

  func testImageEditing_sendsFileAsDataURI() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)
    let pngMagic = Data([137, 80, 78, 71])

    _ = try await model.generate(
      .init(
        prompt: "Turn the cat into a dog",
        files: [.file(data: pngMagic, mediaType: "image/png")],
        n: 1
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string("Turn the cat into a dog"),
        "num_images": .number(1),
        "image_url": .string("data:image/png;base64,iVBORw=="),
      ])
    )
  }

  func testImageEditing_sendsFileAndMaskAsDataURI() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)
    let pngMagic = Data([137, 80, 78, 71])
    let mask = Data([255, 255, 255, 0])

    _ = try await model.generate(
      .init(
        prompt: "Add a flamingo to the pool",
        files: [.file(data: pngMagic, mediaType: "image/png")],
        mask: .file(data: mask, mediaType: "image/png"),
        n: 1
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string("Add a flamingo to the pool"),
        "num_images": .number(1),
        "image_url": .string("data:image/png;base64,iVBORw=="),
        "mask_url": .string("data:image/png;base64,////AA=="),
      ])
    )
  }

  func testImageEditing_sendsURLBasedFile() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)

    _ = try await model.generate(
      .init(
        prompt: "Edit this image",
        files: [.url(URL(string: "https://example.com/input.png")!)],
        n: 1
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string("Edit this image"),
        "num_images": .number(1),
        "image_url": .string("https://example.com/input.png"),
      ])
    )
  }

  func testImageEditing_warnsWhenMultipleFilesAreProvided() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)
    let pngMagic = Data([137, 80, 78, 71])

    let result = try await model.generate(
      .init(
        prompt: "Edit images",
        files: [
          .file(data: pngMagic, mediaType: "image/png"),
          .file(data: pngMagic, mediaType: "image/png"),
        ],
        n: 1
      )
    )

    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertEqual(result.warnings.first?.code, "other")
    XCTAssertTrue(result.warnings.first?.message.contains("only supports a single input image") == true)
  }

  func testImageEditing_allowsImageUrlViaProviderOptions() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)

    _ = try await model.generate(
      .init(
        prompt: "Edit via provider options",
        n: 1,
        providerOptions: ["fal": ["imageUrl": .string("https://example.com/provider-image.png")]]
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string("Edit via provider options"),
        "num_images": .number(1),
        "image_url": .string("https://example.com/provider-image.png"),
      ])
    )
  }

  func testImageEditing_allowsMaskUrlViaProviderOptions() async throws {
    let server = try makeServerWithDefaultResponses()
    let model = createBasicModel(server: server)

    _ = try await model.generate(
      .init(
        prompt: "Inpaint this",
        n: 1,
        providerOptions: [
          "fal": [
            "imageUrl": .string("https://example.com/image.png"),
            "maskUrl": .string("https://example.com/mask.png"),
          ],
        ]
      )
    )

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "prompt": .string("Inpaint this"),
        "num_images": .number(1),
        "image_url": .string("https://example.com/image.png"),
        "mask_url": .string("https://example.com/mask.png"),
      ])
    )
  }

  func testResponseSchema_parsesSingleImageResponse() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "image": .object([
            "url": .string("https://api.example.com/image.png"),
            "width": .number(1024),
            "height": .number(1024),
            "content_type": .string("image/png"),
          ]),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)
    let model = createBasicModel(server: server)

    let result = try await model.generate(.init(prompt: prompt, n: 1))
    XCTAssertEqual(result.images.count, 1)
  }

  func testResponseSchema_parsesMultipleImagesResponse() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "images": .array([
            .object([
              "url": .string("https://api.example.com/image.png"),
              "width": .number(1024),
              "height": .number(1024),
              "content_type": .string("image/png"),
            ]),
            .object([
              "url": .string("https://api.example.com/image.png"),
              "width": .number(1024),
              "height": .number(1024),
              "content_type": .string("image/png"),
            ]),
          ]),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)
    let model = createBasicModel(server: server)

    let result = try await model.generate(.init(prompt: prompt, n: 2))
    XCTAssertEqual(result.images.count, 2)
  }

  func testResponseSchema_handlesNullFileNameAndFileSize() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "images": .array([
            .object([
              "url": .string("https://api.example.com/image.png"),
              "content_type": .string("image/png"),
              "file_name": .null,
              "file_size": .null,
              "width": .number(944),
              "height": .number(1104),
            ]),
          ]),
          "timings": .object(["inference": .number(5.875932216644287)]),
          "seed": .number(328_395_684),
          "has_nsfw_concepts": .array([.bool(false)]),
          "prompt": .string("A female model holding this book, keeping the book unchanged."),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)
    let model = createBasicModel(server: server)

    let result = try await model.generate(.init(prompt: prompt, n: 1))
    XCTAssertEqual(result.images.count, 1)
    XCTAssertEqual(
      result.providerMetadata?["fal"],
      .object([
        "images": .array([
          .object([
            "width": .number(944),
            "height": .number(1104),
            "contentType": .string("image/png"),
            "fileName": .null,
            "fileSize": .null,
            "nsfw": .bool(false),
          ]),
        ]),
        "timings": .object(["inference": .number(5.875932216644287)]),
        "seed": .number(328_395_684),
      ])
    )
  }

  func testResponseSchema_handlesEmptyTimingsObject() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "images": .array([
            .object([
              "url": .string("https://api.example.com/image.png"),
              "content_type": .string("image/png"),
              "file_name": .null,
              "file_size": .null,
              "width": .number(880),
              "height": .number(1184),
            ]),
          ]),
          "timings": .object([:]),
          "seed": .number(235_205_040),
          "has_nsfw_concepts": .array([.bool(false)]),
          "prompt": .string("Change the plates to colorful ones"),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)
    let model = createBasicModel(server: server)

    let result = try await model.generate(.init(prompt: prompt, n: 1))
    XCTAssertEqual(
      result.providerMetadata?["fal"],
      .object([
        "images": .array([
          .object([
            "width": .number(880),
            "height": .number(1184),
            "contentType": .string("image/png"),
            "fileName": .null,
            "fileSize": .null,
            "nsfw": .bool(false),
          ]),
        ]),
        "timings": .object([:]),
        "seed": .number(235_205_040),
      ])
    )
  }

  func testResponseSchema_handlesNullWidthHeightWithImagesArrayOnly() async throws {
    let server = FalTestServer()
    server.responses["POST https://api.example.com/fal-ai/qwen-image"] = .json(
      try JSONEncoder().encode(
        JSONValue.object([
          "images": .array([
            .object([
              "url": .string("https://api.example.com/image.png"),
              "content_type": .string("image/png"),
              "file_name": .string("output.png"),
              "file_size": .number(663_399),
              "width": .null,
              "height": .null,
            ]),
          ]),
          "description": .string("here is an image with null width and height"),
        ])
      )
    )
    server.responses["GET https://api.example.com/image.png"] = .binary("test-binary-content".data(using: .utf8)!)
    let model = createBasicModel(server: server)

    let result = try await model.generate(.init(prompt: prompt, n: 1))
    XCTAssertEqual(
      result.providerMetadata?["fal"],
      .object([
        "images": .array([
          .object([
            "width": .null,
            "height": .null,
            "contentType": .string("image/png"),
            "fileName": .string("output.png"),
            "fileSize": .number(663_399),
          ]),
        ]),
        "description": .string("here is an image with null width and height"),
      ])
    )
  }
}
