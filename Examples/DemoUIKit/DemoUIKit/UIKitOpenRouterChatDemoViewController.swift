import SwiftUI
import UIKit
import Combine

import AIKit
import AIKitElements
import AIKitOpenRouter

final class UIKitOpenRouterChatDemoViewController: UIViewController {
  private let conversationView = ConversationScrollView()
  private let promptInputView = PromptInputView()
  private let composerContainerView = UIView()
  private let errorBanner = UILabel()

  private let controller = OpenRouterChatController()
  private var messages: [ChatMessage] = []
  private var keyboardHeight: CGFloat = 0
  private var composerBottomConstraint: NSLayoutConstraint?
  private var baseBottomOffset: CGFloat = 0
  private let keyboardGap: CGFloat = 20
  private var edgeInteraction: UIScrollEdgeElementContainerInteraction?

  override func viewDidLoad() {
    super.viewDidLoad()

    title = "Chat Demo"
    view.backgroundColor = .systemBackground

    conversationView.dataSource = self
    conversationView.register(HostingMessageCell.self, forCellReuseIdentifier: HostingMessageCell.reuseIdentifier)

    errorBanner.numberOfLines = 0
    errorBanner.textColor = .white
    errorBanner.font = .preferredFont(forTextStyle: .caption1)
    errorBanner.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
    errorBanner.isHidden = true
    errorBanner.translatesAutoresizingMaskIntoConstraints = false

    conversationView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(conversationView)
    view.addSubview(errorBanner)

    NSLayoutConstraint.activate([
      errorBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      errorBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      errorBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),

      conversationView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      conversationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      conversationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      conversationView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    promptInputView.translatesAutoresizingMaskIntoConstraints = false

    composerContainerView.translatesAutoresizingMaskIntoConstraints = false
    composerContainerView.backgroundColor = .clear
    composerContainerView.isOpaque = false
    composerContainerView.clipsToBounds = false
    view.addSubview(composerContainerView)

    let bottomConstraint = composerContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    composerBottomConstraint = bottomConstraint

    NSLayoutConstraint.activate([
      composerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      composerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottomConstraint,
    ])

    composerContainerView.addSubview(promptInputView)
    NSLayoutConstraint.activate([
      promptInputView.topAnchor.constraint(equalTo: composerContainerView.topAnchor),
      promptInputView.leadingAnchor.constraint(equalTo: composerContainerView.leadingAnchor),
      promptInputView.trailingAnchor.constraint(equalTo: composerContainerView.trailingAnchor),
      promptInputView.bottomAnchor.constraint(equalTo: composerContainerView.bottomAnchor),
    ])

    promptInputView.state.onSend = { [weak self] text in
      Task { await self?.controller.send(text: text) }
    }
    promptInputView.state.onStop = { [weak self] in
      Task { await self?.controller.stop() }
    }
    promptInputView.state.onTextChange = { [weak self] _ in
      self?.promptInputView.requestHeightUpdate()
      self?.updateInsets()
    }
    promptInputView.onHeightChange = { [weak self] in
      self?.updateInsets()
    }

    refreshBottomEdgeEffect()

    controller.onUpdate = { [weak self] snapshot in
      self?.apply(snapshot: snapshot)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDefaultsChanged),
      name: UserDefaults.didChangeNotification,
      object: nil
    )
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    configureIfPossible()
    registerForKeyboard()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    unregisterForKeyboard()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    baseBottomOffset = view.safeAreaInsets.bottom * 0.5
    composerBottomConstraint?.constant = -keyboardHeight - keyboardGap + baseBottomOffset
    updateInsets()
    refreshBottomEdgeEffect()
  }

  @objc private func userDefaultsChanged() {
    configureIfPossible()
  }

  private func configureIfPossible() {
    let apiKey = UserDefaults.standard.string(forKey: AppSettings.openRouterAPIKeyKey) ?? ""
    let modelID = UserDefaults.standard.string(forKey: AppSettings.openRouterModelIDKey) ?? AppSettings.defaultOpenRouterModelID
    controller.configureIfPossible(apiKey: apiKey, modelID: modelID)
  }

  private func apply(snapshot: ChatSessionSnapshot) {
    messages = snapshot.messages
    conversationView.reloadData()
    promptInputView.status = (snapshot.status == .streaming || snapshot.status == .submitted) ? .streaming : .ready

    if let error = snapshot.errorDescription {
      errorBanner.text = "  \(error)"
      errorBanner.isHidden = false
    } else {
      errorBanner.isHidden = true
    }
  }

  private func updateInsets() {
    let measuredHeight = composerContainerView.bounds.height
    let fallbackHeight = composerContainerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
    let composerHeight = measuredHeight > 0 ? measuredHeight : fallbackHeight
    conversationView.bottomContentInset = composerHeight + keyboardHeight
    refreshBottomEdgeEffect()
  }

  private func refreshBottomEdgeEffect() {
    conversationView.setBottomEdgeEffect(style: .soft)
    if let edgeInteraction {
      promptInputView.edgeEffectContainerView.removeInteraction(edgeInteraction)
    }
    let interaction = UIScrollEdgeElementContainerInteraction()
    interaction.scrollView = conversationView.scrollView
    interaction.edge = .bottom
    promptInputView.edgeEffectContainerView.addInteraction(interaction)
    edgeInteraction = interaction
  }

  private func registerForKeyboard() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillChange),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
  }

  private func unregisterForKeyboard() {
    NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
  }

  @objc private func keyboardWillChange(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
      let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
      let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
    else { return }

    let frame = frameValue.cgRectValue
    let endFrameInView = view.convert(frame, from: nil)
    let intersection = view.bounds.intersection(endFrameInView)
    let safeBottom = view.safeAreaInsets.bottom
    keyboardHeight = max(0, intersection.height - safeBottom)

    composerBottomConstraint?.constant = -keyboardHeight - keyboardGap + baseBottomOffset
    let options = UIView.AnimationOptions(rawValue: curveValue << 16)

    UIView.animate(withDuration: duration, delay: 0, options: options) {
      self.view.layoutIfNeeded()
      self.updateInsets()
    }
  }
}

extension UIKitOpenRouterChatDemoViewController: ConversationScrollViewDataSource {
  func numberOfMessages(in conversationScrollView: ConversationScrollView) -> Int {
    messages.count
  }

  func conversationScrollView(_ conversationScrollView: ConversationScrollView, cellForMessageAt indexPath: IndexPath) -> UITableViewCell {
    guard let cell = conversationScrollView
      .dequeueReusableCell(withReuseIdentifier: HostingMessageCell.reuseIdentifier, for: indexPath) as? HostingMessageCell
    else {
      return UITableViewCell()
    }

    cell.configure(view: AnyView(DemoChatMessageView(message: messages[indexPath.item])))
    return cell
  }
}

private final class HostingMessageCell: UITableViewCell {
  static let reuseIdentifier = "HostingMessageCell"

  private var hostingController: UIHostingController<AnyView>?

  override func prepareForReuse() {
    super.prepareForReuse()
    hostingController?.rootView = AnyView(EmptyView())
  }

  func configure(view: AnyView) {
    if let hostingController {
      hostingController.rootView = view
      return
    }

    let controller = UIHostingController(rootView: view)
    controller.view.backgroundColor = .clear
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    controller.view.setContentHuggingPriority(.required, for: .vertical)
    controller.view.setContentCompressionResistancePriority(.required, for: .vertical)
    selectionStyle = .none
    contentView.layoutMargins = .init(top: 6, left: 0, bottom: 6, right: 0)
    contentView.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
      controller.view.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
      controller.view.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
    ])
    hostingController = controller
  }
}

@MainActor
private final class OpenRouterChatController {
  var onUpdate: ((ChatSessionSnapshot) -> Void)?

  private var chat: ChatStore?
  private var chatUpdates: AnyCancellable?
  private var configuredKey: String = ""
  private var configuredModelID: String = ""

  func configureIfPossible(apiKey: String, modelID: String) {
    let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)

    if apiKey.isEmpty || modelID.isEmpty {
      chatUpdates?.cancel()
      chatUpdates = nil
      chat = nil
      configuredKey = ""
      configuredModelID = ""
      onUpdate?(.init(
        status: .ready,
        messages: DemoContent.initialMessages,
        errorDescription: apiKey.isEmpty ? "Set an OpenRouter API key in Settings to use this demo." : "Set a model ID in Settings."
      ))
      return
    }

    guard apiKey != configuredKey || modelID != configuredModelID || chat == nil else {
      return
    }

    configuredKey = apiKey
    configuredModelID = modelID

    chatUpdates?.cancel()
    chatUpdates = nil

    let provider = createOpenRouter(.init(apiKey: apiKey))
    let model = provider.chat(modelID)
    let chat = ChatStore(
      model: model,
      initialMessages: DemoContent.initialMessages
    )
    self.chat = chat
    onUpdate?(.init(status: chat.status, messages: chat.messages, errorDescription: chat.errorDescription))
    chatUpdates = chat.objectWillChange.sink { [weak self] _ in
      guard let self, let chat = self.chat else { return }
      self.onUpdate?(.init(status: chat.status, messages: chat.messages, errorDescription: chat.errorDescription))
    }

    onUpdate?(.init(status: .ready, messages: DemoContent.initialMessages, errorDescription: nil))
  }

  func send(text: String) async {
    guard let chat else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return }

    chat.sendMessage(trimmed)
  }

  func stop() async {
    chat?.stop()
  }
}
