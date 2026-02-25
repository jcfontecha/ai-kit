import SwiftUI

@MainActor
final class ConversationScrollDispatcher {
  private var task: Task<Void, Never>?
  private var queue: [Queued] = []

  var isBusy: Bool { task != nil }

  func submit(
    _ steps: [ConversationScrollEngine.Step],
    proxy: ScrollViewProxy,
    forceAnimation: Animation?,
    replaceQueue: Bool,
    reassertLatestIfNeeded: (@MainActor (ScrollViewProxy, Animation?) -> Void)?
  ) {
    guard steps.isEmpty == false else { return }

    let queued = Queued(
      steps: steps,
      proxy: proxy,
      forceAnimation: forceAnimation,
      reassertLatestIfNeeded: reassertLatestIfNeeded
    )

    if replaceQueue {
      queue = [queued]
    } else {
      queue.append(queued)
    }

    runIfNeeded()
  }

  func cancel() {
    task?.cancel()
    task = nil
    queue = []
  }

  // MARK: - Private

  private struct Queued {
    let steps: [ConversationScrollEngine.Step]
    let proxy: ScrollViewProxy
    let forceAnimation: Animation?
    let reassertLatestIfNeeded: (@MainActor (ScrollViewProxy, Animation?) -> Void)?
  }

  private func runIfNeeded() {
    guard task == nil else { return }

    task = Task { @MainActor in
      defer { task = nil }
      while Task.isCancelled == false, queue.isEmpty == false {
        let next = queue.removeFirst()
        await execute(
          next.steps,
          proxy: next.proxy,
          forceAnimation: next.forceAnimation,
          reassertLatestIfNeeded: next.reassertLatestIfNeeded
        )
      }
    }
  }

  private func execute(
    _ steps: [ConversationScrollEngine.Step],
    proxy: ScrollViewProxy,
    forceAnimation: Animation?,
    reassertLatestIfNeeded: (@MainActor (ScrollViewProxy, Animation?) -> Void)?
  ) async {
    for step in steps {
      if Task.isCancelled { return }

      switch step {
      case .yield:
        await Task.yield()

      case .scrollTo(let target, let stepAnchor, let animated):
        let id: String
        let anchor: UnitPoint
        switch target {
        case .bottomSentinel:
          id = ConversationScrollConstants.bottomSentinelID
        case .reservedTailSentinel:
          id = ConversationScrollConstants.reservedTailSentinelID
        case .message(let messageID):
          id = messageID
        }

        switch stepAnchor {
        case .top:
          anchor = .top
        case .bottom:
          anchor = .bottom
        }

        if animated {
          withAnimation(forceAnimation ?? .default) {
            proxy.scrollTo(id, anchor: anchor)
          }
        } else {
          proxy.scrollTo(id, anchor: anchor)
        }

      case .reassertLatestIfNeeded:
        reassertLatestIfNeeded?(proxy, forceAnimation)
      }
    }
  }
}
