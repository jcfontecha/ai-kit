import SwiftUI
import AIKit
import AIKitCore
import AIKitElements

struct ToolDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ToolPartView(tool: pendingTool, statusStrings: statusStrings)
      ToolPartView(tool: runningTool, statusStrings: statusStrings)
      ToolPartView(tool: completedTool, statusStrings: statusStrings)
      ToolPartView(tool: errorTool, statusStrings: statusStrings)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var baseInput: JSONValue {
    .object([
      "location": .string("San Francisco"),
      "units": .string("fahrenheit"),
    ])
  }

  private var statusStrings: ToolStatusStrings {
    .init(loading: "Loading", success: "Completed", error: "Error")
  }

  private var pendingTool: ChatToolPart {
    .init(
      toolCallID: "tool-1",
      toolName: "fetch_weather_data",
      title: "fetch_weather_data",
      input: baseInput,
      state: .inputStreaming
    )
  }

  private var runningTool: ChatToolPart {
    .init(
      toolCallID: "tool-2",
      toolName: "fetch_weather_data",
      title: "fetch_weather_data",
      input: baseInput,
      state: .inputAvailable
    )
  }

  private var completedTool: ChatToolPart {
    .init(
      toolCallID: "tool-3",
      toolName: "fetch_weather_data",
      title: "fetch_weather_data",
      input: baseInput,
      output: .object([
        "temperature": .string("68°F"),
        "conditions": .string("Sunny"),
      ]),
      state: .outputAvailable(preliminary: false)
    )
  }

  private var errorTool: ChatToolPart {
    .init(
      toolCallID: "tool-4",
      toolName: "fetch_weather_data",
      title: "fetch_weather_data",
      input: baseInput,
      state: .outputError(errorText: "Network error")
    )
  }
}
