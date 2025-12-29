import XCTest
import AIKit
import AIKitMacro

@AIModel
struct E2EPerson: Codable, Sendable, Equatable {
  @Field("Full name", minLength: 1, maxLength: 100)
  var name: String

  @Field("Age in years", range: 0...150)
  var age: Int?
}

@AIModel
struct E2EWeatherInput: Codable, Sendable, Equatable {
  @Field("City name", minLength: 1, maxLength: 100)
  var city: String
}

final class AIKitE2ETests: XCTestCase {
  func testMacros_generateSchema_andGenerateTextUsesIt() async throws {
    let schema = E2EPerson.schema.jsonSchema.value

    XCTAssertEqual(schema["type"], .string("object"))

    guard case let .array(required)? = schema["required"] else {
      return XCTFail("expected required[] in schema")
    }
    XCTAssertTrue(required.contains(.string("name")))
    XCTAssertFalse(required.contains(.string("age")))

    guard
      case let .object(properties)? = schema["properties"],
      case let .object(nameSchema)? = properties["name"]
    else {
      return XCTFail("expected properties.name in schema")
    }

    XCTAssertEqual(nameSchema["type"], .string("string"))
    XCTAssertEqual(nameSchema["minLength"], .number(1))
    XCTAssertEqual(nameSchema["maxLength"], .number(100))
    XCTAssertEqual(nameSchema["description"], .string("Full name"))

    let model = RecordingLanguageModel { request in
      XCTAssertEqual(
        request.responseFormat,
        .jsonSchema(schema: E2EPerson.schema.jsonSchema, name: "E2EPerson", description: nil)
      )
      return ModelResponse(
        content: [.text("{\"name\":\"Ada\"}")],
        finishReason: .stop,
        rawFinishReason: "stop"
      )
    }

    let ai = AIClient(model: model)
    let result = try await ai.generate(
      "Return a JSON object for a person.",
      output: Output.typedObject(E2EPerson.self)
    )

    XCTAssertEqual(try result.output, E2EPerson(name: "Ada", age: nil))
  }

  func testStreamText_typedObjectEmitsPartialOutput_andFinalOutput() async throws {
    let model = RecordingLanguageModel(
      generate: { _ in
        .init(content: [], finishReason: .stop, rawFinishReason: "stop")
      },
      stream: { request in
        XCTAssertEqual(
          request.responseFormat,
          .jsonSchema(schema: E2EPerson.schema.jsonSchema, name: "E2EPerson", description: nil)
        )

        return makeStream([
          .streamStart(),
          .startStep(),
          .textStart(id: "t1", providerMetadata: nil),
          .textDelta(id: "t1", text: "{\"name\":\"Ada\"}", providerMetadata: nil),
          .textEnd(id: "t1", providerMetadata: nil),
          .finishStep(finishReason: .stop, rawFinishReason: "stop"),
          .finish(finishReason: .stop),
        ])
      }
    )

    let ai = AIClient(model: model)
    let stream = ai.stream(
      "Return a person JSON object.",
      output: Output.typedObject(E2EPerson.self)
    )

    var partials: [E2EPerson.Partial] = []
    for try await partial in stream.partialOutputStream {
      partials.append(partial)
    }

    XCTAssertEqual(partials.last?.name, "Ada")
    let output = try await stream.output
    XCTAssertEqual(output, E2EPerson(name: "Ada", age: nil))
  }

  func testToolLoopAgent_streamEmitsToolApprovalRequest_fromMacroSchemaToolInput() async throws {
    let toolID = ToolID<E2EWeatherInput, String>("weather")
    var tools = ToolRegistry()
    tools.register(
      toolID,
      ToolSpec(
        title: "Weather",
        description: "Get weather for a city.",
        inputSchema: E2EWeatherInput.schema,
        needsApproval: { _, _ in true },
        execute: { _, _ in .final("sunny") }
      )
    )

    let call = ToolCall(
      toolCallID: "call-1",
      toolName: "weather",
      inputJSON: "{\"city\":\"NYC\"}",
      input: .object(["city": .string("NYC")])
    )

    let model = RecordingLanguageModel(
      generate: { _ in
        .init(content: [], finishReason: .stop, rawFinishReason: "stop")
      },
      stream: { request in
        XCTAssertEqual(request.tools.count, 1)
        XCTAssertEqual(request.tools.first?.name, "weather")
        XCTAssertEqual(request.tools.first?.inputSchema, E2EWeatherInput.schema.jsonSchema)

        return makeStream([
          .streamStart(),
          .startStep(),
          .toolCall(call),
          .finishStep(finishReason: .toolCalls, rawFinishReason: "tool_calls"),
          .finish(finishReason: .toolCalls),
        ])
      }
    )

    let agent = ToolLoopAgent<Void, Output.Text>(
      model: model,
      tools: tools,
      stopWhen: [Stop.stepCountIs(1)],
      output: Output.text()
    )

    let result = await agent.stream(prompt: "What is the weather in NYC?")

    var approvalRequest: ToolApprovalRequest?
    for try await part in result.fullStream {
      if case let .toolApprovalRequest(req) = part {
        approvalRequest = req
        break
      }
    }

    XCTAssertEqual(approvalRequest?.toolCallID, "call-1")
    XCTAssertEqual(approvalRequest?.toolCall?.toolName, "weather")
  }
}
