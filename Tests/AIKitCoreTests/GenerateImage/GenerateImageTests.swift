import XCTest
import AIKitProviders
@testable import AIKitCore

final class GenerateImageTests: XCTestCase {
  private let prompt = "sunny day at the beach"
  private let testDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z

  // 1x1 transparent PNG
  private let pngBase64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="
  // 1x1 black JPEG
  private let jpegBase64 =
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k="
  // 1x1 transparent GIF
  private let gifBase64 = "R0lGODlhAQABAIAAAAUEBAAAACwAAAAAAQABAAACAkQBADs="

  private func base64Data(_ base64: String) -> Data {
    Data(base64Encoded: base64) ?? Data()
  }

  private actor MockImageModel: ImageModel {
    let id: String
    private let onGenerate: @Sendable (ImageRequest) async throws -> ImageResponse
    private let onMaxImagesPerCall: (@Sendable () async -> Int?)?

    private(set) var capturedRequests: [ImageRequest] = []
    private(set) var maxImagesPerCallInvocationCount: Int = 0

    init(
      id: String = "mock-model-id",
      maxImagesPerCall: (@Sendable () async -> Int?)? = nil,
      onGenerate: @escaping @Sendable (ImageRequest) async throws -> ImageResponse
    ) {
      self.id = id
      self.onMaxImagesPerCall = maxImagesPerCall
      self.onGenerate = onGenerate
    }

    func generate(_ request: ImageRequest) async throws -> ImageResponse {
      capturedRequests.append(request)
      return try await onGenerate(request)
    }

    func maxImagesPerCall() async -> Int? {
      maxImagesPerCallInvocationCount += 1
      return await onMaxImagesPerCall?()
    }
  }

  func testForwardsArgsToModel() async throws {
    let model = MockImageModel { _ in
      ImageResponse(
        images: [.base64(self.pngBase64)],
        response: .init(timestamp: self.testDate, modelID: "test-model", headers: [:])
      )
    }

    _ = try await generateImage(
      .init(
        model: model,
        prompt: .multimodal(
          text: prompt,
          images: [.base64(pngBase64)],
          mask: .base64(pngBase64)
        ),
        n: 1,
        size: "1024x1024",
        aspectRatio: "16:9",
        seed: 12345,
        providerOptions: ["mock-provider": ["style": .string("vivid")]],
        headers: ["custom-request-header": "request-header-value"]
      )
    )

    let requests = await model.capturedRequests
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(
      requests[0],
      ImageRequest(
        prompt: prompt,
        files: [
          .file(data: base64Data(pngBase64), mediaType: "image/png"),
        ],
        mask: .file(data: base64Data(pngBase64), mediaType: "image/png"),
        n: 1,
        size: "1024x1024",
        aspectRatio: "16:9",
        seed: 12345,
        providerOptions: ["mock-provider": ["style": .string("vivid")]],
        headers: ["custom-request-header": "request-header-value"]
      )
    )
  }

  func testReturnsWarnings() async throws {
    let model = MockImageModel { _ in
      ImageResponse(
        images: [.base64(self.pngBase64)],
        warnings: [.init(message: "Setting is not supported", code: "other")],
        response: .init()
      )
    }

    let result = try await generateImage(.init(model: model, prompt: .text(prompt)))
    XCTAssertEqual(result.warnings, [.init(message: "Setting is not supported", code: "other")])
  }

  func testDetectsMediaTypesForReturnedBase64Images() async throws {
    let model = MockImageModel { _ in
      ImageResponse(
        images: [.base64(self.pngBase64), .base64(self.jpegBase64)],
        response: .init()
      )
    }

    let result = try await generateImage(.init(model: model, prompt: .text(prompt)))
    XCTAssertEqual(
      result.images,
      [
        .init(data: base64Data(pngBase64), mediaType: "image/png"),
        .init(data: base64Data(jpegBase64), mediaType: "image/jpeg"),
      ]
    )
    XCTAssertEqual(result.image, .init(data: base64Data(pngBase64), mediaType: "image/png"))
  }

  func testReturnsGeneratedImagesForReturnedBytes() async throws {
    let pngData = base64Data(pngBase64)
    let jpegData = base64Data(jpegBase64)

    let model = MockImageModel { _ in
      ImageResponse(images: [.data(pngData), .data(jpegData)], response: .init())
    }

    let result = try await generateImage(.init(model: model, prompt: .text(prompt)))
    XCTAssertEqual(
      result.images,
      [
        .init(data: pngData, mediaType: "image/png"),
        .init(data: jpegData, mediaType: "image/jpeg"),
      ]
    )
  }

  func testSplitsIntoMultipleCallsUsingModelMaxImagesPerCall() async throws {
    let base64Images = [pngBase64, jpegBase64, gifBase64]
    let model = MockImageModel(
      maxImagesPerCall: { 2 },
      onGenerate: { request in
        let images = request.n == 2 ? base64Images.prefix(2) : base64Images.suffix(1)
        return ImageResponse(images: images.map { .base64($0) }, response: .init())
      }
    )

    let result = try await generateImage(
      .init(
        model: model,
        prompt: .text(prompt),
        n: 3,
        size: "1024x1024",
        aspectRatio: "16:9",
        seed: 12345,
        providerOptions: ["mock-provider": ["style": .string("vivid")]],
        headers: ["custom-request-header": "request-header-value"]
      )
    )

    XCTAssertEqual(result.images.map { $0.data }, base64Images.map(base64Data))
    let maxImagesPerCallInvocationCount = await model.maxImagesPerCallInvocationCount
    let requestCounts = await model.capturedRequests.map(\.n)
    XCTAssertEqual(maxImagesPerCallInvocationCount, 1)
    XCTAssertEqual(requestCounts, [2, 1])
  }

  func testThrowsNoImageGeneratedErrorWhenNoImagesReturned() async throws {
    let model = MockImageModel { _ in
      ImageResponse(
        images: [],
        response: .init(timestamp: self.testDate, modelID: "test-model", headers: nil)
      )
    }

    do {
      _ = try await generateImage(.init(model: model, prompt: .text(prompt)))
      XCTFail("Expected error")
    } catch let error as NoImageGeneratedError {
      XCTAssertEqual(error.message, "No image generated.")
      XCTAssertEqual(
        error.responses,
        [.init(timestamp: testDate, modelID: "test-model", headers: nil)]
      )
    }
  }

  func testAggregatesProviderMetadataAcrossCallsWithGatewayMerge() async throws {
    final class CounterBox: @unchecked Sendable {
      private let lock = NSLock()
      private var value: Int = 0

      func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
      }
    }

    let counter = CounterBox()
    let model = MockImageModel(
      maxImagesPerCall: { 1 },
      onGenerate: { request in
        let callIndex = counter.next()
        if request.n != 1 { XCTFail("Unexpected n") }
        if callIndex == 0 {
          return ImageResponse(
            images: [.base64(self.pngBase64)],
            response: .init(),
            providerMetadata: [
              "gateway": .object([
                "images": .array([]),
                "routing": .object(["provider": .string("test1")]),
                "cost": .string("0.01"),
              ]),
            ]
          )
        }
        return ImageResponse(
          images: [.base64(self.jpegBase64)],
          response: .init(),
          providerMetadata: [
            "gateway": .object([
              "images": .array([]),
              "routing": .object(["provider": .string("test2")]),
              "generationId": .string("gen-123"),
            ]),
          ]
        )
      }
    )

    let result = try await generateImage(.init(model: model, prompt: .text(prompt), n: 2))

    XCTAssertEqual(
      result.providerMetadata["gateway"],
      .object([
        "routing": .object(["provider": .string("test2")]),
        "generationId": .string("gen-123"),
        "cost": .string("0.01"),
      ])
    )
  }

  func testParsesDataURLPromptImages() async throws {
    let jpegDataURL = URL(string: "data:image/jpeg;base64,\(jpegBase64)")!

    let model = MockImageModel { _ in
      ImageResponse(images: [.base64(self.pngBase64)], response: .init())
    }

    _ = try await generateImage(
      .init(
        model: model,
        prompt: .multimodal(text: prompt, images: [.url(jpegDataURL)], mask: nil)
      )
    )

    let requests = await model.capturedRequests
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(
      requests[0].files,
      [.file(data: base64Data(jpegBase64), mediaType: "image/jpeg")]
    )
  }
}
