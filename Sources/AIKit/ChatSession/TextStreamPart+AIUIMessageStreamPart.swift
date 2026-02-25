import Foundation
import AIKitProviders

extension AsyncThrowingStream where Element == TextStreamPart, Failure == Error {
  func flatMapToUIMessageStreamParts() -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    AsyncThrowingStream<AIUIMessageStreamPart, Error> { continuation in
      Task {
        do {
          for try await part in self {
            for mapped in part.toAIUIMessageStreamParts() {
              continuation.yield(mapped)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}

private extension TextStreamPart {
  func toAIUIMessageStreamParts() -> [AIUIMessageStreamPart] {
    switch self {
    case .start:
      return []
    case .startStep:
      return [.startStep]
    case .finishStep:
      return [.finishStep]

    case .textStart(let id, let providerMetadata):
      return [.textStart(id: id, providerMetadata: providerMetadata)]
    case .textDelta(let id, let text, let providerMetadata):
      return [.textDelta(id: id, delta: text, providerMetadata: providerMetadata)]
    case .textEnd(let id, let providerMetadata):
      return [.textEnd(id: id, providerMetadata: providerMetadata)]

    case .reasoningStart(let id, let providerMetadata):
      return [.reasoningStart(id: id, providerMetadata: providerMetadata)]
    case .reasoningDelta(let id, let text, let providerMetadata):
      return [.reasoningDelta(id: id, delta: text, providerMetadata: providerMetadata)]
    case .reasoningEnd(let id, let providerMetadata):
      return [.reasoningEnd(id: id, providerMetadata: providerMetadata)]

    case .toolInputStart(let id, let toolName, let providerMetadata, let providerExecuted, let dynamic, let title):
      return [.toolInputStart(.init(
        toolCallID: id,
        toolName: toolName,
        providerExecuted: providerExecuted,
        dynamic: dynamic,
        title: title,
        providerMetadata: providerMetadata
      ))]
    case .toolInputDelta(let id, let delta, let providerMetadata):
      return [.toolInputDelta(.init(toolCallID: id, inputTextDelta: delta, providerMetadata: providerMetadata))]
    case .toolInputEnd(let id, _):
      return [.toolInputEnd(toolCallID: id)]

    case .toolCall(let call):
      if call.invalid == true, let errorText = call.error as String? {
        return [.toolInputError(.init(
          toolCallID: call.toolCallID,
          toolName: call.toolName,
          input: .string(call.inputJSON),
          providerExecuted: call.providerExecuted,
          providerMetadata: call.providerMetadata,
          dynamic: call.dynamic,
          errorText: errorText,
          title: call.title
        ))]
      }
      return [.toolInputAvailable(.init(
        toolCallID: call.toolCallID,
        toolName: call.toolName,
        input: call.input ?? .null,
        providerExecuted: call.providerExecuted,
        providerMetadata: call.providerMetadata,
        dynamic: call.dynamic,
        title: call.title
      ))]

    case .toolResult(let result):
      return [.toolOutputAvailable(.init(
        toolCallID: result.toolCallID,
        output: result.output,
        providerExecuted: result.providerExecuted,
        dynamic: result.dynamic,
        preliminary: result.preliminary
      ))]

    case .toolError(let error):
      return [.toolOutputError(.init(
        toolCallID: error.toolCallID,
        errorText: error.error,
        providerExecuted: error.providerExecuted,
        dynamic: error.dynamic
      ))]

    case .toolOutputDenied(let denied):
      return [.toolOutputDenied(toolCallID: denied.toolCallID)]

    case .toolApprovalRequest(let request):
      return [.toolApprovalRequest(approvalID: request.approvalID, toolCallID: request.toolCallID)]

    case .toolApprovalResponse:
      return []

    case .finish(let finishReason, _, _):
      return [.finish(finishReason: finishReason, messageMetadata: nil)]

    case .abort:
      return [.abort]

    case .raw(let json):
      return [.raw(json)]

    case .error(let message):
      return [.error(message)]

    case .source, .file:
      return []
    }
  }
}
