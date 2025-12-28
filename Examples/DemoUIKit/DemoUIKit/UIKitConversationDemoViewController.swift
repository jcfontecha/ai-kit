import UIKit
import AIKit
import AIKitElements

final class UIKitConversationDemoViewController: UIViewController {
  private let conversationView = ConversationScrollView()
  private let composerView = DemoComposerView()
  private var messages: [ChatMessage] = DemoContent.initialMessages

  override func viewDidLoad() {
    super.viewDidLoad()

    title = "Conversation"
    view.backgroundColor = .systemBackground

    conversationView.dataSource = self
    conversationView.register(ConversationMessageCell.self, forCellReuseIdentifier: ConversationMessageCell.reuseIdentifier)

    conversationView.translatesAutoresizingMaskIntoConstraints = false
    composerView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(conversationView)
    view.addSubview(composerView)

    NSLayoutConstraint.activate([
      conversationView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      conversationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      conversationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      conversationView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      composerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      composerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      composerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      composerView.heightAnchor.constraint(equalToConstant: 64),
    ])

    conversationView.bottomContentInset = 64 + 12
    conversationView.reloadData()
  }
}

extension UIKitConversationDemoViewController: ConversationScrollViewDataSource {
  func numberOfMessages(in conversationScrollView: ConversationScrollView) -> Int {
    messages.count
  }

  func conversationScrollView(_ conversationScrollView: ConversationScrollView, cellForMessageAt indexPath: IndexPath) -> UITableViewCell {
    guard let cell = conversationScrollView
      .dequeueReusableCell(withReuseIdentifier: ConversationMessageCell.reuseIdentifier, for: indexPath) as? ConversationMessageCell
    else {
      return UITableViewCell()
    }

    cell.configure(with: messages[indexPath.row])
    return cell
  }
}

private final class DemoComposerView: UIView {
  private let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)

    backgroundColor = .secondarySystemBackground

    label.text = "Composer"
    label.font = .preferredFont(forTextStyle: .callout)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false

    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class ConversationMessageCell: UITableViewCell {
  static let reuseIdentifier = "ConversationMessageCell"

  private let bubbleView = UIView()
  private let messageLabel = UILabel()

  private var userLeadingConstraint: NSLayoutConstraint?
  private var userTrailingConstraint: NSLayoutConstraint?
  private var assistantLeadingConstraint: NSLayoutConstraint?
  private var assistantTrailingConstraint: NSLayoutConstraint?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    selectionStyle = .none
    contentView.layoutMargins = .init(top: 6, left: 0, bottom: 6, right: 0)

    bubbleView.layer.cornerRadius = 14
    bubbleView.translatesAutoresizingMaskIntoConstraints = false

    messageLabel.numberOfLines = 0
    messageLabel.font = .preferredFont(forTextStyle: .body)
    messageLabel.translatesAutoresizingMaskIntoConstraints = false

    bubbleView.addSubview(messageLabel)
    contentView.addSubview(bubbleView)

    NSLayoutConstraint.activate([
      messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
      messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
      messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
      messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),

      bubbleView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
      bubbleView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
    ])

    userLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 60)
    userTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    assistantLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
    assistantTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -60)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(with message: ChatMessage) {
    messageLabel.text = text(from: message)

    switch message.role {
    case .user:
      bubbleView.backgroundColor = UIColor.secondarySystemBackground
      assistantLeadingConstraint?.isActive = false
      assistantTrailingConstraint?.isActive = false
      userLeadingConstraint?.isActive = true
      userTrailingConstraint?.isActive = true

    case .assistant, .system, .tool:
      bubbleView.backgroundColor = UIColor.systemGray6
      userLeadingConstraint?.isActive = false
      userTrailingConstraint?.isActive = false
      assistantLeadingConstraint?.isActive = true
      assistantTrailingConstraint?.isActive = true

    @unknown default:
      bubbleView.backgroundColor = UIColor.systemGray6
    }
  }

  private func text(from message: ChatMessage) -> String {
    let parts = message.parts.compactMap { part -> String? in
      if case let .text(text) = part { return text.text }
      return nil
    }
    return parts.joined(separator: "\n")
  }
}
