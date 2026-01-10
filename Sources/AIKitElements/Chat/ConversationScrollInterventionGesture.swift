#if canImport(UIKit)
import SwiftUI
import UIKit

/// Observes vertical scroll intent without claiming horizontal swipes.
///
/// This avoids stealing horizontal drags from parent containers (e.g. sliding sidebars) while still
/// letting Conversation react to user-initiated scrolling (cancel auto-follow, etc.).
struct ConversationScrollInterventionGesture: UIViewRepresentable {
  let onChanged: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.onChanged = onChanged
    context.coordinator.installIfNeeded(from: uiView)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onChanged: onChanged)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var onChanged: () -> Void

    private weak var scrollView: UIScrollView?
    private weak var pan: UIPanGestureRecognizer?

    init(onChanged: @escaping () -> Void) {
      self.onChanged = onChanged
    }

    func installIfNeeded(from leafView: UIView) {
      guard let scrollView = nearestScrollView(from: leafView) else { return }
      if self.scrollView === scrollView, pan != nil { return }

      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      pan.maximumNumberOfTouches = 1
      pan.cancelsTouchesInView = false
      pan.delegate = self

      scrollView.addGestureRecognizer(pan)

      self.scrollView = scrollView
      self.pan = pan
    }

    private func nearestScrollView(from leafView: UIView) -> UIScrollView? {
      var view: UIView? = leafView
      while let current = view {
        if let scroll = current as? UIScrollView { return scroll }
        view = current.superview
      }
      return nil
    }

    @objc
    private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      switch recognizer.state {
      case .began, .changed:
        onChanged()
      default:
        break
      }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
      let v = pan.velocity(in: pan.view)
      return abs(v.y) > abs(v.x) * 1.15
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      true
    }
  }
}
#endif

