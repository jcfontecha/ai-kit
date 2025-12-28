import SwiftUI
import UIKit

import AIKit

public final class PromptInputView: UIView {
  public final class State: ObservableObject {
    @Published public var text: String
    @Published public var status: ChatSessionStatus

    public var onSend: ((String) -> Void)?
    public var onStop: (() -> Void)?
    public var onTextChange: ((String) -> Void)?

    public init(text: String = "", status: ChatSessionStatus = .ready) {
      self.text = text
      self.status = status
    }
  }

  public let state: State
  public var onHeightChange: (() -> Void)?

  public var edgeEffectContainerView: UIView { glassContainerView }

  private let glassContainerView = UIView()
  private let glassView = UIVisualEffectView()
  private var hostingController: UIHostingController<PromptInputHost>?
  private var heightConstraint: NSLayoutConstraint?
  private var lastHeight: CGFloat = 0

  public init(state: State = .init()) {
    self.state = state
    super.init(frame: .zero)
    setupView()
    configureHosting()
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public var text: String {
    get { state.text }
    set { state.text = newValue }
  }

  public var status: ChatSessionStatus {
    get { state.status }
    set { state.status = newValue }
  }

  public func requestHeightUpdate() {
    guard let hostingController else { return }
    let targetWidth: CGFloat
    if bounds.width > 0 {
      targetWidth = bounds.width
    } else {
      targetWidth = superview?.bounds.width ?? 0
    }
    guard targetWidth > 0 else { return }
    let size = hostingController.sizeThatFits(in: CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
    guard size.height > 0 else { return }
    if abs(size.height - lastHeight) > 0.5 {
      lastHeight = size.height
      heightConstraint?.constant = size.height
      onHeightChange?()
    }
  }

  private func setupView() {
    translatesAutoresizingMaskIntoConstraints = false

    glassContainerView.translatesAutoresizingMaskIntoConstraints = false
    glassContainerView.backgroundColor = .clear
    glassContainerView.isOpaque = false
    glassContainerView.clipsToBounds = false

    glassView.translatesAutoresizingMaskIntoConstraints = false
    glassView.backgroundColor = .clear
    glassView.isOpaque = false
    glassView.clipsToBounds = true
    glassView.layer.cornerRadius = 24
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect(style: .clear)
      glassEffect.tintColor = .clear
      glassView.effect = glassEffect
    } else {
      glassView.effect = UIBlurEffect(style: .systemMaterial)
    }

    addSubview(glassContainerView)
    glassContainerView.addSubview(glassView)

    NSLayoutConstraint.activate([
      glassContainerView.topAnchor.constraint(equalTo: topAnchor),
      glassContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      glassContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      glassContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

      glassView.topAnchor.constraint(equalTo: glassContainerView.topAnchor, constant: 12),
      glassView.leadingAnchor.constraint(equalTo: glassContainerView.leadingAnchor, constant: 12),
      glassView.trailingAnchor.constraint(equalTo: glassContainerView.trailingAnchor, constant: -12),
      glassView.bottomAnchor.constraint(equalTo: glassContainerView.bottomAnchor, constant: -8),
    ])
  }

  private func configureHosting() {
    let host = UIHostingController(rootView: PromptInputHost(state: state))
    host.view.backgroundColor = .clear
    host.view.isOpaque = false
    host.view.clipsToBounds = false
    host.view.translatesAutoresizingMaskIntoConstraints = false
    if #available(iOS 16.0, *) {
      host.sizingOptions = [.intrinsicContentSize]
    }

    hostingController = host
    glassView.contentView.addSubview(host.view)

    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
      host.view.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
      host.view.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
    ])

    let heightConstraint = heightAnchor.constraint(equalToConstant: 1)
    heightConstraint.priority = .required
    heightConstraint.isActive = true
    self.heightConstraint = heightConstraint
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    requestHeightUpdate()
  }
}

private struct PromptInputHost: View {
  @ObservedObject var state: PromptInputView.State

  var body: some View {
    PromptInputElements(
      text: $state.text,
      status: state.status,
      onSend: { message in
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        state.text = ""
        state.onSend?(trimmed)
      },
      onStop: {
        state.onStop?()
      }
    )
    .onChange(of: state.text) { newValue in
      state.onTextChange?(newValue)
    }
    .padding(.horizontal, 0)
    .padding(.vertical, 8)
  }
}
