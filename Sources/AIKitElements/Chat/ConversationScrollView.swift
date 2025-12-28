#if canImport(UIKit)
import UIKit

public protocol ConversationScrollViewDataSource: AnyObject {
  func numberOfMessages(in conversationScrollView: ConversationScrollView) -> Int
  func conversationScrollView(_ conversationScrollView: ConversationScrollView, cellForMessageAt indexPath: IndexPath) -> UITableViewCell
}

public protocol ConversationScrollViewDelegate: AnyObject {
  func conversationScrollViewDidScroll(_ conversationScrollView: ConversationScrollView)
}

public extension ConversationScrollViewDelegate {
  func conversationScrollViewDidScroll(_ conversationScrollView: ConversationScrollView) {}
}

public final class ConversationScrollView: UIView {
  public weak var dataSource: ConversationScrollViewDataSource? {
    didSet { tableView.dataSource = self }
  }
  
  public weak var delegate: ConversationScrollViewDelegate?
  
  public var bottomContentInset: CGFloat = 0 {
    didSet { updateInsets() }
  }
  
  public var contentInsets: UIEdgeInsets = .init(top: 16, left: 0, bottom: 16, right: 0) {
    didSet { updateInsets() }
  }
  
  private let tableView: UITableView
  private var isPinnedToBottom: Bool = true
  
  public var scrollView: UIScrollView { tableView }
  private var bottomEdgeInteraction: AnyObject?
  
  public override init(frame: CGRect) {
    tableView = UITableView(frame: .zero, style: .plain)
    tableView.separatorStyle = .none
    tableView.alwaysBounceVertical = true
    tableView.alwaysBounceHorizontal = false
    tableView.isDirectionalLockEnabled = true
    tableView.showsHorizontalScrollIndicator = false
    tableView.backgroundColor = .clear
    tableView.estimatedRowHeight = 44
    tableView.rowHeight = UITableView.automaticDimension
    
    super.init(frame: frame)
    
    addSubview(tableView)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: topAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    
    tableView.dataSource = self
    tableView.delegate = self
    
    updateInsets()
  }
  
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  public func register(_ cellClass: AnyClass?, forCellReuseIdentifier identifier: String) {
    tableView.register(cellClass, forCellReuseIdentifier: identifier)
  }
  
  public func register(_ nib: UINib?, forCellReuseIdentifier identifier: String) {
    tableView.register(nib, forCellReuseIdentifier: identifier)
  }
  
  public func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UITableViewCell {
    tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
  }
  
  public func reloadData() {
    let wasPinned = isPinnedToBottom
    tableView.reloadData()
    tableView.layoutIfNeeded()
    if wasPinned {
      scrollToBottom(animated: false)
    }
  }

  public func setBottomEdgeEffect(style: UIScrollEdgeEffect.Style) {
    tableView.bottomEdgeEffect.style = style
    tableView.bottomEdgeEffect.isHidden = false
  }

  public func attachBottomEdgeEffect(to containerView: UIView) {
    let interaction = UIScrollEdgeElementContainerInteraction()
    interaction.scrollView = tableView
    interaction.edge = .bottom
    containerView.addInteraction(interaction)
    bottomEdgeInteraction = interaction
  }

  public func scrollToBottom(animated: Bool) {
    let count = tableView.numberOfRows(inSection: 0)
    guard count > 0 else { return }
    let indexPath = IndexPath(row: count - 1, section: 0)
    tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
  }
  
  private func updateInsets() {
    let previousMaxOffset = tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
    let wasPinned = tableView.contentOffset.y >= (previousMaxOffset - 12)
    let inset = UIEdgeInsets(
      top: contentInsets.top,
      left: contentInsets.left,
      bottom: contentInsets.bottom + bottomContentInset,
      right: contentInsets.right
    )
    tableView.contentInset = inset
    tableView.scrollIndicatorInsets = inset
    tableView.layoutIfNeeded()
    if wasPinned {
      scrollToBottom(animated: false)
    }
  }
  
  private func updatePinnedState() {
    let maxOffset = tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
    let threshold: CGFloat = 12
    isPinnedToBottom = tableView.contentOffset.y >= (maxOffset - threshold)
  }
}

extension ConversationScrollView: UITableViewDataSource {
  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    dataSource?.numberOfMessages(in: self) ?? 0
  }
  
  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    guard let dataSource else {
      return UITableViewCell()
    }
    return dataSource.conversationScrollView(self, cellForMessageAt: indexPath)
  }
}

extension ConversationScrollView: UITableViewDelegate {
  public func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if abs(scrollView.contentOffset.x) > 0.5 {
      scrollView.contentOffset.x = 0
    }
    updatePinnedState()
    delegate?.conversationScrollViewDidScroll(self)
  }
}
#else
import Foundation

@available(*, unavailable, message: "ConversationScrollView is only available on UIKit platforms.")
public protocol ConversationScrollViewDataSource: AnyObject {}

@available(*, unavailable, message: "ConversationScrollView is only available on UIKit platforms.")
public protocol ConversationScrollViewDelegate: AnyObject {}

@available(*, unavailable, message: "ConversationScrollView is only available on UIKit platforms.")
public final class ConversationScrollView: NSObject {}
#endif
