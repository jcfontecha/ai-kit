import XCTest
import AIKitProviders
@testable import AIKitReplicate

final class ReplicateImageModelTests: XCTestCase {
  private let prompt = "The Loch Ness monster getting a manicure"
  private let testDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z

  private func preparePredictionResponse(output: JSONValue) -> Data {
    let json: JSONValue = .object([
      "id": .string("s7x1e3dcmhrmc0cm8rbatcneec"),
      "model": .string("black-forest-labs/flux-schnell"),
      "version": .string("dp-4d0bcc010b3049749a251855f12800be"),
      "input": .object([
        "num_outputs": .number(1),
        "prompt": .string("The Loch Ness Monster getting a manicure"),
      ]),
      "logs": .string(""),
      "output": output,
      "data_removed": .bool(false),
      "error": .null,
      "status": .string("processing"),
      "created_at": .string("2025-01-08T13:24:38.692Z"),
      "urls": .object([
        "cancel": .string("https://api.replicate.com/v1/predictions/s7x1e3dcmhrmc0cm8rbatcneec/cancel"),
        "get": .string("https://api.replicate.com/v1/predictions/s7x1e3dcmhrmc0cm8rbatcneec"),
        "stream": .string("https://stream.replicate.com/v1/files/bcwr-123"),
      ]),
    ])
    return (try? JSONEncoder().encode(json)) ?? Data()
  }

  func testGenerate_passesModelAndSettings() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .array([.string("https://replicate.delivery/xezq/abc/out-0.webp")])),
      headers: ["content-type": "application/json", "content-length": "646"]
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")

    _ = try await model.generate(
      ImageRequest(
        prompt: prompt,
        files: nil,
        mask: nil,
        n: 1,
        size: "1024x768",
        aspectRatio: "3:4",
        seed: 123,
        providerOptions: [
          "replicate": ["style": .string("realistic_image")],
          "other": ["something": .string("else")],
        ]
      )
    )

    let body = server.calls[0].requestBodyJSON
    XCTAssertEqual(
      body,
      .object([
        "input": .object([
          "prompt": .string(prompt),
          "num_outputs": .number(1),
          "aspect_ratio": .string("3:4"),
          "size": .string("1024x768"),
          "seed": .number(123),
          "style": .string("realistic_image"),
        ]),
      ])
    )
  }

  func testGenerate_callsCorrectURL() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")

    _ = try await model.generate(ImageRequest(prompt: prompt, n: 1))

    XCTAssertEqual(server.calls[0].requestMethod, "POST")
    XCTAssertEqual(
      server.calls[0].requestUrl,
      "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"
    )
  }

  func testGenerate_fallsBackToPredictionsCreateWhenModelPredictionsReturns404() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/prunaai/z-image-turbo-img2img/predictions"] = .json(
      (try? JSONEncoder().encode(JSONValue.object(["detail": .string("The requested resource could not be found."), "status": .number(404)])))
        ?? Data(),
      headers: ["content-type": "application/problem+json"],
      status: 404
    )
    server.responses["GET https://api.replicate.com/v1/models/prunaai/z-image-turbo-img2img/versions"] = .json(
      (try? JSONEncoder().encode(JSONValue.object([
        "next": .null,
        "previous": .null,
        "results": .array([
          .object([
            "id": .string("5c958e90e0f904240629ee35c69196e3bd790b5528c0696705ebdb1656871dd8"),
          ]),
        ]),
      ]))) ?? Data()
    )
    server.responses["POST https://api.replicate.com/v1/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("prunaai/z-image-turbo-img2img")

    _ = try await model.generate(ImageRequest(prompt: prompt, n: 1))

    XCTAssertEqual(server.calls[0].requestUrl, "https://api.replicate.com/v1/models/prunaai/z-image-turbo-img2img/predictions")
    XCTAssertEqual(server.calls[1].requestUrl, "https://api.replicate.com/v1/models/prunaai/z-image-turbo-img2img/versions")
    XCTAssertEqual(server.calls[2].requestUrl, "https://api.replicate.com/v1/predictions")

    if case .object(let body)? = server.calls[2].requestBodyJSON,
       case .string(let version)? = body["version"] {
      XCTAssertEqual(version, "5c958e90e0f904240629ee35c69196e3bd790b5528c0696705ebdb1656871dd8")
    } else {
      XCTFail("Expected version in /predictions request body")
    }
  }

  func testGenerate_passesHeadersAndPreferWait() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp")),
      headers: ["content-type": "application/json", "content-length": "646"]
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(
      .init(
        apiToken: "test-api-token",
        headers: ["Custom-Provider-Header": "provider-header-value"],
        transport: server.transport()
      )
    )

    let model = provider.image("black-forest-labs/flux-schnell")
    _ = try await model.generate(
      ImageRequest(
        prompt: prompt,
        n: 1,
        headers: ["Custom-Request-Header": "request-header-value"]
      )
    )

    XCTAssertEqual(
      server.calls[0].requestHeaders,
      [
        "authorization": "Bearer test-api-token",
        "content-type": "application/json",
        "custom-provider-header": "provider-header-value",
        "custom-request-header": "request-header-value",
        "prefer": "wait",
        "user-agent": "ai-sdk/replicate/0.0.0-test",
      ]
    )
  }

  func testGenerate_setsCustomPreferWaitTimeAndDoesNotIncludeInBody() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")
    _ = try await model.generate(
      ImageRequest(
        prompt: prompt,
        n: 1,
        providerOptions: [
          "replicate": [
            "maxWaitTimeInSeconds": .number(120),
            "guidance_scale": .number(7.5),
          ],
        ]
      )
    )

    XCTAssertEqual(server.calls[0].requestHeaders["prefer"], "wait=120")

    if case .object(let body)? = server.calls[0].requestBodyJSON,
       case .object(let input)? = body["input"] {
      XCTAssertNil(input["maxWaitTimeInSeconds"])
      XCTAssertEqual(input["guidance_scale"], .number(7.5))
    } else {
      XCTFail("Unexpected request body")
    }
  }

  func testGenerate_downloadsImagesFromOutputArrayOrString() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .array([.string("https://replicate.delivery/xezq/abc/out-0.webp")]))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")
    let result = try await model.generate(ImageRequest(prompt: prompt, n: 1))

    XCTAssertEqual(result.images, [.data(Data("test-binary-content".utf8))])
    XCTAssertEqual(server.calls[1].requestMethod, "GET")
    XCTAssertEqual(server.calls[1].requestUrl, "https://replicate.delivery/xezq/abc/out-0.webp")
  }

  func testGenerate_pollsProcessingPredictionWithoutCreatingAnotherPrediction() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/openai/gpt-image-2/predictions"] = .json(
      (try? JSONEncoder().encode(JSONValue.object([
        "id": .string("pred_123"),
        "status": .string("processing"),
        "output": .null,
        "urls": .object([
          "get": .string("https://api.replicate.com/v1/predictions/pred_123"),
        ]),
      ]))) ?? Data()
    )
    server.responses["GET https://api.replicate.com/v1/predictions/pred_123"] = .json(
      (try? JSONEncoder().encode(JSONValue.object([
        "id": .string("pred_123"),
        "status": .string("succeeded"),
        "output": .array([.string("https://replicate.delivery/xezq/abc/out-0.png")]),
      ]))) ?? Data()
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.png"] = .binary(Data("test-binary-content".utf8))

    let model = ReplicateImageModel(
      modelId: "openai/gpt-image-2",
      config: .init(
        baseURL: "https://api.replicate.com/v1",
        headers: { ["authorization": "Bearer test-api-token", "user-agent": "ai-sdk/replicate/0.0.0-test"] },
        transport: server.transport(),
        predictionPollIntervalNanoseconds: 0
      )
    )

    let result = try await model.generate(ImageRequest(prompt: prompt, n: 1))

    XCTAssertEqual(result.images, [.data(Data("test-binary-content".utf8))])
    XCTAssertEqual(
      server.calls.map { "\($0.requestMethod) \($0.requestUrl)" },
      [
        "POST https://api.replicate.com/v1/models/openai/gpt-image-2/predictions",
        "GET https://api.replicate.com/v1/predictions/pred_123",
        "GET https://replicate.delivery/xezq/abc/out-0.png",
      ]
    )
  }

  func testGenerate_returnsResponseMetadataWithTimestampAndHeaders() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .array([.string("https://replicate.delivery/xezq/abc/out-0.webp")])),
      headers: [
        "content-length": "646",
        "content-type": "application/json",
        "custom-response-header": "response-header-value",
      ]
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let fixedDate = testDate
    let model = ReplicateImageModel(
      modelId: "black-forest-labs/flux-schnell",
      config: .init(
        baseURL: "https://api.replicate.com/v1",
        headers: { ["authorization": "Bearer test-api-token", "user-agent": "ai-sdk/replicate/0.0.0-test"] },
        transport: server.transport(),
        currentDate: { [fixedDate] in fixedDate }
      )
    )

    let result = try await model.generate(ImageRequest(prompt: prompt, n: 1))
    XCTAssertEqual(
      result.response,
      .init(
        timestamp: testDate,
        modelID: "black-forest-labs/flux-schnell",
        headers: [
          "content-length": "646",
          "content-type": "application/json",
          "custom-response-header": "response-header-value",
        ]
      )
    )
  }

  func testGenerate_versionedModelsPostToPredictionsAndIncludeVersion() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image(
      "bytedance/sdxl-lightning-4step:5599ed30703defd1d160a25a63321b4dec97101d98b4674bcc56e41f62f35637"
    )

    _ = try await model.generate(ImageRequest(prompt: prompt, n: 1))

    XCTAssertEqual(server.calls[0].requestMethod, "POST")
    XCTAssertEqual(server.calls[0].requestUrl, "https://api.replicate.com/v1/predictions")
    XCTAssertEqual(
      server.calls[0].requestBodyJSON,
      .object([
        "input": .object([
          "prompt": .string(prompt),
          "num_outputs": .number(1),
        ]),
        "version": .string("5599ed30703defd1d160a25a63321b4dec97101d98b4674bcc56e41f62f35637"),
      ])
    )
  }

  func testGenerate_imageEditing_sendsImageWhenURLFileProvided() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")

    _ = try await model.generate(
      ImageRequest(
        prompt: "Add a hat to the person",
        files: [.url(URL(string: "https://example.com/input.jpg")!)],
        n: 1
      )
    )

    XCTAssertEqual(
      server.calls[0].requestBodyJSON,
      .object([
        "input": .object([
          "prompt": .string("Add a hat to the person"),
          "num_outputs": .number(1),
          "image": .string("https://example.com/input.jpg"),
        ]),
      ])
    )
  }

  func testGenerate_imageEditing_convertsFileDataToDataURI() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")

    let pngHeader = Data([137, 80, 78, 71, 13, 10, 26, 10])
    _ = try await model.generate(
      ImageRequest(
        prompt: "Transform this image",
        files: [.file(data: pngHeader, mediaType: "image/png")],
        n: 1
      )
    )

    guard case .object(let root)? = server.calls[0].requestBodyJSON,
          case .object(let input)? = root["input"],
          case .string(let image)? = input["image"] else {
      return XCTFail("Unexpected request body")
    }
    XCTAssertTrue(image.hasPrefix("data:image/png;base64,"))
    XCTAssertEqual(input["prompt"], .string("Transform this image"))
  }

  func testGenerate_imageEditing_sendsMaskForInpainting() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")

    _ = try await model.generate(
      ImageRequest(
        prompt: "Replace the masked area with a tree",
        files: [.url(URL(string: "https://example.com/input.jpg")!)],
        mask: .url(URL(string: "https://example.com/mask.png")!),
        n: 1
      )
    )

    XCTAssertEqual(
      server.calls[0].requestBodyJSON,
      .object([
        "input": .object([
          "prompt": .string("Replace the masked area with a tree"),
          "num_outputs": .number(1),
          "image": .string("https://example.com/input.jpg"),
          "mask": .string("https://example.com/mask.png"),
        ]),
      ])
    )
  }

  func testGenerate_imageEditing_warnsWhenMultipleFilesProvided() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("black-forest-labs/flux-schnell")

    let result = try await model.generate(
      ImageRequest(
        prompt: "Edit multiple images",
        files: [
          .url(URL(string: "https://example.com/input1.jpg")!),
          .url(URL(string: "https://example.com/input2.jpg")!),
        ],
        n: 1
      )
    )

    XCTAssertEqual(
      result.warnings,
      [
        .init(
          message: "This Replicate model only supports a single input image. Additional images are ignored.",
          code: "other"
        ),
      ]
    )
    XCTAssertEqual(server.calls[0].requestBodyJSON, .object([
      "input": .object([
        "prompt": .string("Edit multiple images"),
        "num_outputs": .number(1),
        "image": .string("https://example.com/input1.jpg"),
      ]),
    ]))
  }

  func testGenerate_flux2Models_maxImagesPerCallAndInputKeys() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-2-pro/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let flux2 = provider.image("black-forest-labs/flux-2-pro")

    let maxImagesPerCall = await flux2.maxImagesPerCall()
    XCTAssertEqual(maxImagesPerCall, 8)

    _ = try await flux2.generate(
      ImageRequest(
        prompt: "Combine styles from reference images",
        files: [
          .url(URL(string: "https://example.com/reference1.jpg")!),
          .url(URL(string: "https://example.com/reference2.jpg")!),
          .url(URL(string: "https://example.com/reference3.jpg")!),
        ],
        n: 1
      )
    )

    XCTAssertEqual(server.calls[0].requestUrl, "https://api.replicate.com/v1/models/black-forest-labs/flux-2-pro/predictions")
    XCTAssertEqual(server.calls[0].requestBodyJSON, .object([
      "input": .object([
        "prompt": .string("Combine styles from reference images"),
        "num_outputs": .number(1),
        "input_image": .string("https://example.com/reference1.jpg"),
        "input_image_2": .string("https://example.com/reference2.jpg"),
        "input_image_3": .string("https://example.com/reference3.jpg"),
      ]),
    ]))
  }

  func testGenerate_flux2Models_warnsAndIgnoresMask() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-2-pro/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let flux2 = provider.image("black-forest-labs/flux-2-pro")

    let result = try await flux2.generate(
      ImageRequest(
        prompt: "Edit with mask",
        files: [.url(URL(string: "https://example.com/input.jpg")!)],
        mask: .url(URL(string: "https://example.com/mask.png")!),
        n: 1
      )
    )

    XCTAssertEqual(
      result.warnings,
      [.init(message: "Flux-2 models do not support mask input. The mask will be ignored.", code: "other")]
    )

    guard case .object(let root)? = server.calls[0].requestBodyJSON,
          case .object(let input)? = root["input"] else {
      return XCTFail("Unexpected request body")
    }
    XCTAssertNil(input["mask"])
  }

  func testGenerate_flux2Models_warnsWhenMoreThan8ImagesProvided() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/black-forest-labs/flux-2-pro/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let flux2 = provider.image("black-forest-labs/flux-2-pro")

    let urls = (1...9).map { URL(string: "https://example.com/img\($0).jpg")! }
    let result = try await flux2.generate(
      ImageRequest(
        prompt: "Too many images",
        files: urls.map { .url($0) },
        n: 1
      )
    )

    XCTAssertEqual(
      result.warnings,
      [.init(message: "Flux-2 models support up to 8 input images. Additional images are ignored.", code: "other")]
    )

    guard case .object(let root)? = server.calls[0].requestBodyJSON,
          case .object(let input)? = root["input"] else {
      return XCTFail("Unexpected request body")
    }
    XCTAssertEqual(input["input_image"], .string("https://example.com/img1.jpg"))
    XCTAssertEqual(input["input_image_8"], .string("https://example.com/img8.jpg"))
    XCTAssertNil(input["input_image_9"])
  }

  func testGenerate_gptImage15_usesExpectedInputKeysAndIgnoresMaskSizeAndSeed() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/openai/gpt-image-1.5/predictions"] = .json(
      preparePredictionResponse(output: .array([.string("https://replicate.delivery/xezq/abc/out-0.webp")])),
      headers: ["content-type": "application/json", "content-length": "646"]
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("openai/gpt-image-1.5")

    let result = try await model.generate(
      ImageRequest(
        prompt: prompt,
        files: [
          .url(URL(string: "https://example.com/input1.jpg")!),
          .url(URL(string: "https://example.com/input2.jpg")!),
        ],
        mask: .url(URL(string: "https://example.com/mask.png")!),
        n: 2,
        size: "1024x1024",
        aspectRatio: "1:1",
        seed: 123
      )
    )

    XCTAssertEqual(
      result.warnings,
      [
        .init(
          message: "openai/gpt-image models do not support mask input. The mask will be ignored.",
          code: "other"
        ),
      ]
    )

    guard case .object(let root)? = server.calls[0].requestBodyJSON,
          case .object(let input)? = root["input"] else {
      return XCTFail("Unexpected request body")
    }

    XCTAssertEqual(input["prompt"], .string(prompt))
    XCTAssertEqual(input["number_of_images"], .number(2))
    XCTAssertEqual(input["aspect_ratio"], .string("1:1"))
    XCTAssertEqual(
      input["input_images"],
      .array([.string("https://example.com/input1.jpg"), .string("https://example.com/input2.jpg")])
    )

    XCTAssertNil(input["num_outputs"])
    XCTAssertNil(input["mask"])
    XCTAssertNil(input["size"])
    XCTAssertNil(input["seed"])
  }

  func testGenerate_nanoBanana2_usesImageInputAndOmitsUnsupportedGenericKeys() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/google/nano-banana-2/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("google/nano-banana-2")

    _ = try await model.generate(
      ImageRequest(
        prompt: prompt,
        files: [
          .url(URL(string: "https://example.com/input1.jpg")!),
          .url(URL(string: "https://example.com/input2.jpg")!),
        ],
        n: 2,
        size: "1024x1024",
        aspectRatio: "16:9",
        seed: 123
      )
    )

    guard case .object(let root)? = server.calls[0].requestBodyJSON,
          case .object(let input)? = root["input"] else {
      return XCTFail("Unexpected request body")
    }

    XCTAssertEqual(input["prompt"], .string(prompt))
    XCTAssertEqual(input["aspect_ratio"], .string("16:9"))
    XCTAssertEqual(
      input["image_input"],
      .array([.string("https://example.com/input1.jpg"), .string("https://example.com/input2.jpg")])
    )
    XCTAssertNil(input["num_outputs"])
    XCTAssertNil(input["number_of_images"])
    XCTAssertNil(input["size"])
    XCTAssertNil(input["seed"])
  }

  func testGenerate_nanoBananaPro_usesImageInput() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/google/nano-banana-pro/predictions"] = .json(
      preparePredictionResponse(output: .string("https://replicate.delivery/xezq/abc/out-0.webp"))
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("google/nano-banana-pro")

    _ = try await model.generate(
      ImageRequest(
        prompt: "Edit with references",
        files: [
          .url(URL(string: "https://example.com/reference1.jpg")!),
          .url(URL(string: "https://example.com/reference2.jpg")!),
        ],
        n: 1
      )
    )

    guard case .object(let root)? = server.calls[0].requestBodyJSON,
          case .object(let input)? = root["input"] else {
      return XCTFail("Unexpected request body")
    }

    XCTAssertEqual(
      input["image_input"],
      .array([.string("https://example.com/reference1.jpg"), .string("https://example.com/reference2.jpg")])
    )
    XCTAssertNil(input["image"])
  }

  func testMaxImagesPerCall_gptImage15_returns10() async throws {
    let model = ReplicateImageModel(
      modelId: "openai/gpt-image-1.5",
      config: .init(
        baseURL: "https://api.replicate.com/v1",
        headers: { [:] },
        transport: ReplicateTestServer().transport()
      )
    )

    let maxImagesPerCall = await model.maxImagesPerCall()
    XCTAssertEqual(maxImagesPerCall, 10)
  }

  func testGenerate_gptImage2_usesExpectedInputKeysAndIgnoresMaskSizeAndSeed() async throws {
    let server = ReplicateTestServer()
    server.responses["POST https://api.replicate.com/v1/models/openai/gpt-image-2/predictions"] = .json(
      preparePredictionResponse(output: .array([.string("https://replicate.delivery/xezq/abc/out-0.webp")])),
      headers: ["content-type": "application/json", "content-length": "646"]
    )
    server.responses["GET https://replicate.delivery/xezq/abc/out-0.webp"] = .binary(Data("test-binary-content".utf8))

    let provider = createReplicate(.init(apiToken: "test-api-token", transport: server.transport()))
    let model = provider.image("openai/gpt-image-2")

    let result = try await model.generate(
      ImageRequest(
        prompt: prompt,
        files: [
          .url(URL(string: "https://example.com/input1.jpg")!),
          .url(URL(string: "https://example.com/input2.jpg")!),
        ],
        mask: .url(URL(string: "https://example.com/mask.png")!),
        n: 2,
        size: "1024x1024",
        aspectRatio: "3:2",
        seed: 123,
        providerOptions: [
          "replicate": [
            "moderation": .string("low"),
            "user_id": .string("geppetto-ios-app"),
          ],
        ]
      )
    )

    XCTAssertEqual(
      result.warnings,
      [
        .init(
          message: "openai/gpt-image models do not support mask input. The mask will be ignored.",
          code: "other"
        ),
      ]
    )

    guard case .object(let root)? = server.calls[0].requestBodyJSON,
          case .object(let input)? = root["input"] else {
      return XCTFail("Unexpected request body")
    }

    XCTAssertEqual(input["prompt"], .string(prompt))
    XCTAssertEqual(input["number_of_images"], .number(2))
    XCTAssertEqual(input["aspect_ratio"], .string("3:2"))
    XCTAssertEqual(input["moderation"], .string("low"))
    XCTAssertEqual(input["user_id"], .string("geppetto-ios-app"))
    XCTAssertEqual(
      input["input_images"],
      .array([.string("https://example.com/input1.jpg"), .string("https://example.com/input2.jpg")])
    )

    XCTAssertNil(input["num_outputs"])
    XCTAssertNil(input["mask"])
    XCTAssertNil(input["size"])
    XCTAssertNil(input["seed"])
  }

  func testMaxImagesPerCall_gptImage2_returns10() async throws {
    let model = ReplicateImageModel(
      modelId: "openai/gpt-image-2",
      config: .init(
        baseURL: "https://api.replicate.com/v1",
        headers: { [:] },
        transport: ReplicateTestServer().transport()
      )
    )

    let maxImagesPerCall = await model.maxImagesPerCall()
    XCTAssertEqual(maxImagesPerCall, 10)
  }
}
