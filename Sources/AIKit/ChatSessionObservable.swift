#if canImport(Combine)
import Combine
import Foundation
import AIKitCore

@MainActor
public final class ChatSessionObservable: ObservableObject {
  @Published public private(set) var snapshot: ChatSessionSnapshot

  public var status: ChatSessionStatus { snapshot.status }
  public var messages: [ChatMessage] { snapshot.messages }
  public var errorDescription: String? { snapshot.errorDescription }

  private let session: ChatSession
  private var task: Task<Void, Never>?

  public init(
    session: ChatSession,
    bufferingPolicy: AsyncStream<ChatSessionSnapshot>.Continuation.BufferingPolicy = .bufferingNewest(1)
  ) {
    self.session = session
    self.snapshot = .init(status: .ready, messages: [], errorDescription: nil)

    task = Task { [weak self] in
      guard let self else { return }
      self.snapshot = await session.snapshot()
      let updates = await session.updates(bufferingPolicy: bufferingPolicy)
      for await snap in updates {
        self.snapshot = snap
      }
    }
  }

  deinit {
    task?.cancel()
  }
}
#endif

