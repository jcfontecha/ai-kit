import Foundation

actor ChatSessionUpdateBroadcaster {
  private var continuations: [UUID: AsyncStream<ChatSessionSnapshot>.Continuation] = [:]

  func makeStream(
    initial: ChatSessionSnapshot,
    bufferingPolicy: AsyncStream<ChatSessionSnapshot>.Continuation.BufferingPolicy
  ) -> AsyncStream<ChatSessionSnapshot> {
    let id = UUID()

    return AsyncStream(ChatSessionSnapshot.self, bufferingPolicy: bufferingPolicy) { continuation in
      continuations[id] = continuation
      continuation.yield(initial)
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeContinuation(id: id) }
      }
    }
  }

  func broadcast(_ snapshot: ChatSessionSnapshot) {
    for (_, continuation) in continuations {
      continuation.yield(snapshot)
    }
  }

  private func removeContinuation(id: UUID) {
    continuations.removeValue(forKey: id)
  }
}

