import XCTest
@testable import AIKitOpenAI
import AIKitProviders

final class OpenAIChatStreamTests: XCTestCase {
  private let testPrompt: [ModelMessage] = [.user("Hello")]

  private func streamChunksForTextDeltas(
    id: String = "chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP",
    model: String = "gpt-4o-2024-08-06",
    content: [String],
    finishReason: String = "stop",
    usage: String
  ) -> [String] {
    var chunks: [String] = []
    chunks.append(
      "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}\n\n"
    )
    for text in content {
      chunks.append(
        "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\(text)\"},\"finish_reason\":null}]}\n\n"
      )
    }
    chunks.append(
      "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"\(finishReason)\",\"logprobs\":null}]}\n\n"
    )
    chunks.append(
      "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"choices\":[],\"usage\":\(usage)}\n\n"
    )
    chunks.append("data: [DONE]\n\n")
    return chunks
  }

  func testStreamTextDeltas() async throws {
    let chunks = streamChunksForTextDeltas(
      content: ["Hello", ", ", "World!"],
      finishReason: "stop",
      usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}"
    )

    let server = OpenAITestServer(config: [
      OpenAITestServer.chatURL: .init(type: .streamChunks(chunks))
    ])

    let model = server.chatModel("gpt-4o")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(textDeltas, ["Hello", ", ", "World!"])

    guard let finish = parts.last, case let .finish(finishReason, usage, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .stop)
    XCTAssertEqual(usage.inputTokens?.total, 17)
    XCTAssertEqual(usage.outputTokens?.total, 227)
  }

  func testStreamToolCall() async throws {
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-tool\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-4o-2024-08-06\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"index\":0,\"id\":\"call_abc\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-tool\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-4o-2024-08-06\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"location\\\":\"}}]},\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-tool\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-4o-2024-08-06\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"SF\\\"}\"}}]},\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-tool\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-4o-2024-08-06\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-tool\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"gpt-4o-2024-08-06\",\"choices\":[],\"usage\":{\"prompt_tokens\":17,\"completion_tokens\":10,\"total_tokens\":27}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenAITestServer(config: [
      OpenAITestServer.chatURL: .init(type: .streamChunks(chunks))
    ])

    let model = server.chatModel("gpt-4o")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let toolInputStarts = parts.compactMap { part -> String? in
      guard case let .toolInputStart(_, toolName, _, _, _, _) = part else { return nil }
      return toolName
    }
    XCTAssertEqual(toolInputStarts, ["get_weather"])

    let toolCalls = parts.compactMap { part -> ToolCall? in
      guard case let .toolCall(call) = part else { return nil }
      return call
    }
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolCalls.first?.toolCallID, "call_abc")
    XCTAssertEqual(toolCalls.first?.toolName, "get_weather")
    XCTAssertEqual(toolCalls.first?.inputJSON, "{\"location\":\"SF\"}")

    guard let finish = parts.last, case let .finish(finishReason, _, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .toolCalls)
  }
}
