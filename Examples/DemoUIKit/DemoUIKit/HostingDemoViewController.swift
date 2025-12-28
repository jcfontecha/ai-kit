import SwiftUI
import UIKit

final class HostingDemoViewController: UIViewController {
  private let build: @MainActor () -> AnyView
  private var hostingController: UIHostingController<AnyView>?

  init(title: String, build: @escaping @MainActor () -> AnyView) {
    self.build = build
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    let hosted = UIHostingController(rootView: AnyView(build().padding(16)))
    hosted.view.translatesAutoresizingMaskIntoConstraints = false
    hosted.view.backgroundColor = .clear

    addChild(hosted)
    view.addSubview(hosted.view)
    NSLayoutConstraint.activate([
      hosted.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      hosted.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hosted.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hosted.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    hosted.didMove(toParent: self)

    hostingController = hosted
  }
}
