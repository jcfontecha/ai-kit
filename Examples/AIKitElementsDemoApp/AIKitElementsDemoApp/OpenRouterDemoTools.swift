import Foundation
import AIKit

func demoTools() -> ToolRegistry {
  var tools = ToolRegistry()

  let sleepTool = ToolID<JSONValue, JSONValue>("sleep_ms")
  tools.register(sleepTool, .init(
    title: "Sleep (ms)",
    description: "Waits for the provided duration (milliseconds) before returning.",
    inputSchema: .manual(
      jsonSchema: .object(
        properties: [
          "milliseconds": .integer(description: "How long to sleep, in ms.", minimum: 0, maximum: 5_000),
        ],
        required: ["milliseconds"]
      ),
      name: "SleepInput"
    ),
    execute: { input, _ in
      let delay: Int = {
        guard case let .object(obj) = input, let field = obj["milliseconds"] else { return 0 }
        switch field {
        case .number(let number):
          return Int(number)
        case .string(let text):
          return Int(text) ?? 0
        default:
          return 0
        }
      }()
      if delay > 0 {
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
      }
      return .final(.object([
        "sleptMs": .number(Double(delay)),
        "message": .string("Slept for \(delay)ms.")
      ]))
    }
  ))

  let echoTool = ToolID<JSONValue, JSONValue>("echo_with_delay")
  tools.register(echoTool, .init(
    title: "Echo (delayed)",
    description: "Echoes the input text after an optional delay.",
    inputSchema: .manual(
      jsonSchema: .object(
        properties: [
          "text": .string(description: "Text to echo back."),
          "delayMs": .integer(description: "Optional delay before responding (ms).", minimum: 0, maximum: 5_000),
        ],
        required: ["text"]
      ),
      name: "EchoInput"
    ),
    execute: { input, _ in
      let delay: Int = {
        guard case let .object(obj) = input, let field = obj["delayMs"] else { return 200 }
        switch field {
        case .number(let number):
          return Int(number)
        case .string(let text):
          return Int(text) ?? 200
        default:
          return 200
        }
      }()
      let text: String = {
        guard case let .object(obj) = input, let field = obj["text"] else { return "" }
        if case let .string(value) = field { return value }
        return ""
      }()
      if delay > 0 {
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
      }
      return .final(.object([
        "echoedText": .string(text),
        "delayMs": .number(Double(delay))
      ]))
    }
  ))

  return tools
}
