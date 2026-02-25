import Foundation
import FoundationModels
import AIKitProviders

func appleToolCalls(from entries: [Transcript.Entry]) -> [ToolCall] {
  var result: [ToolCall] = []

  for entry in entries {
    switch entry {
    case .toolCalls(let calls):
      for call in calls {
        let input = appleJSONValue(from: call.arguments)
        let inputJSON = call.arguments.jsonString
        result.append(
          .init(
            toolCallID: call.id,
            toolName: call.toolName,
            inputJSON: inputJSON,
            input: input
          )
        )
      }
    case .instructions, .prompt, .toolOutput, .response:
      continue
    @unknown default:
      continue
    }
  }

  return result
}

func appleResponseText(from entries: [Transcript.Entry]) -> String {
  var chunks: [String] = []

  for entry in entries {
    switch entry {
    case .response(let response):
      for segment in response.segments {
        switch segment {
        case .text(let text):
          chunks.append(text.content)
        case .structure(let structured):
          chunks.append(structured.content.jsonString)
        @unknown default:
          continue
        }
      }
    case .instructions, .prompt, .toolCalls, .toolOutput:
      continue
    @unknown default:
      continue
    }
  }

  return chunks.joined()
}

func appleResponseID(from entries: [Transcript.Entry]) -> String {
  for entry in entries.reversed() {
    switch entry {
    case .response(let response):
      return response.id
    case .instructions, .prompt, .toolCalls, .toolOutput:
      continue
    @unknown default:
      continue
    }
  }
  return ""
}
