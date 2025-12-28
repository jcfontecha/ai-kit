import UIKit

final class ComponentDetailViewController: UITableViewController {
  private let component: ComponentDefinition
  private var headerView: ComponentHeaderView?

  init(component: ComponentDefinition) {
    self.component = component
    super.init(style: .insetGrouped)
    title = component.name
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

    let header = ComponentHeaderView(name: component.name, summary: component.summary)
    tableView.tableHeaderView = header
    headerView = header
    updateHeaderSizeIfNeeded()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateHeaderSizeIfNeeded()
  }

  override func numberOfSections(in tableView: UITableView) -> Int {
    1
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    component.variants.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    let variant = component.variants[indexPath.row]

    var configuration = UIListContentConfiguration.subtitleCell()
    configuration.text = variant.title
    configuration.secondaryText = variant.description
    configuration.textProperties.numberOfLines = 1
    configuration.secondaryTextProperties.numberOfLines = 2

    cell.contentConfiguration = configuration
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    defer { tableView.deselectRow(at: indexPath, animated: true) }

    let variant = component.variants[indexPath.row]
    if component.id == "conversation", variant.id == "conversation/basic" {
      navigationController?.pushViewController(UIKitConversationDemoViewController(), animated: true)
      return
    }

    let vc = HostingDemoViewController(title: variant.title, build: variant.build)
    navigationController?.pushViewController(vc, animated: true)
  }

  private func updateHeaderSizeIfNeeded() {
    guard let headerView else { return }

    let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
    let size = headerView.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )

    if headerView.frame.size.height != size.height {
      headerView.frame.size = CGSize(width: tableView.bounds.width, height: size.height)
      tableView.tableHeaderView = headerView
    }
  }
}

private final class ComponentHeaderView: UIView {
  private let nameLabel = UILabel()
  private let summaryLabel = UILabel()

  init(name: String, summary: String) {
    super.init(frame: .zero)

    nameLabel.text = name
    nameLabel.font = UIFont.preferredFont(forTextStyle: .largeTitle).withWeight(.bold)
    nameLabel.numberOfLines = 0

    summaryLabel.text = summary
    summaryLabel.font = UIFont.preferredFont(forTextStyle: .body)
    summaryLabel.textColor = .secondaryLabel
    summaryLabel.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [nameLabel, summaryLabel])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private extension UIFont {
  func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
