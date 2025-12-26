import Foundation

/// A simple cancellation primitive that can be passed through to providers.
///
/// Swift concurrency cancellation via `Task` should remain the primary mechanism, but this mirrors
/// the JS AI SDK `abortSignal` use cases where cancellation is driven by an external handle.
public actor CancellationToken {
  private var cancelled = false
  private var handlers: [@Sendable () -> Void] = []

  public init() {}

  public func cancel() {
    guard cancelled == false else { return }
    cancelled = true
    let currentHandlers = handlers
    handlers.removeAll()
    for handler in currentHandlers {
      handler()
    }
  }

  public var isCancelled: Bool {
    cancelled
  }

  public func onCancel(_ handler: @escaping @Sendable () -> Void) {
    if cancelled {
      handler()
      return
    }
    handlers.append(handler)
  }
}
