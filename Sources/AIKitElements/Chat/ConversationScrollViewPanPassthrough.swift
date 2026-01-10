#if canImport(UIKit)
import SwiftUI
import UIKit

/// Helps parent containers (e.g. sidebars) receive horizontal swipes over a vertical ScrollView.
///
/// Installs a horizontal-only `UIPanGestureRecognizer` on the nearest `UIScrollView` and makes the
/// scroll view's own pan recognizer wait for it to fail. Vertical pans bypass this recognizer, so
/// normal scrolling remains unaffected.
struct ConversationScrollViewPanPassthrough: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.installIfNeeded(from: uiView)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    private weak var scrollView: UIScrollView?
    private weak var horizontalPan: UIPanGestureRecognizer?

    func installIfNeeded(from leafView: UIView) {
      guard let scrollView = nearestScrollView(from: leafView) else { return }
      if self.scrollView === scrollView, horizontalPan != nil { return }

      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      pan.maximumNumberOfTouches = 1
      pan.cancelsTouchesInView = false
      pan.delegate = self

      scrollView.addGestureRecognizer(pan)
      scrollView.panGestureRecognizer.require(toFail: pan)

      self.scrollView = scrollView
      self.horizontalPan = pan
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
      // Intentionally empty: this recognizer exists purely to keep the vertical scroll view
      // from claiming horizontal swipes, so parent containers can handle them.
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
      let v = pan.velocity(in: pan.view)
      return abs(v.x) > abs(v.y) * 1.15
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      true
    }
  }
}
#endif

