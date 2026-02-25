import Foundation
@testable import AIKitOpenClaw

actor OpenClawTestWebSocket: OpenClawWebSocket {
  struct Closed: Error {}

  private(set) var sentTexts: [String] = []
  private var onSend: (@Sendable (String) async -> Void)?

  private var queue: [String] = []
  private var waiters: [CheckedContinuation<String, Error>] = []
  private var isClosed = false

  func send(text: String) async throws {
    guard isClosed == false else { throw Closed() }
    sentTexts.append(text)
    await onSend?(text)
  }

  func setOnSend(_ handler: (@Sendable (String) async -> Void)?) {
    onSend = handler
  }

  func receiveText() async throws -> String {
    guard isClosed == false else { throw Closed() }
    if queue.isEmpty == false {
      return queue.removeFirst()
    }
    return try await withCheckedThrowingContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func pushIncoming(_ text: String) {
    guard isClosed == false else { return }
    if waiters.isEmpty == false {
      let waiter = waiters.removeFirst()
      waiter.resume(returning: text)
      return
    }
    queue.append(text)
  }

  func close() async {
    guard isClosed == false else { return }
    isClosed = true
    let pending = waiters
    waiters.removeAll()
    queue.removeAll()
    for waiter in pending {
      waiter.resume(throwing: Closed())
    }
  }
}
