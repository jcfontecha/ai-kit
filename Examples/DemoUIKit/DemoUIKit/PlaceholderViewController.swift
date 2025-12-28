import UIKit

final class PlaceholderViewController: UIViewController {
  private let detail: String

  init(title: String, detail: String) {
    self.detail = detail
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

    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.numberOfLines = 0

    let detailLabel = UILabel()
    detailLabel.text = detail
    detailLabel.font = .preferredFont(forTextStyle: .body)
    detailLabel.textColor = .secondaryLabel
    detailLabel.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
    stack.axis = .vertical
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
    ])
  }
}

