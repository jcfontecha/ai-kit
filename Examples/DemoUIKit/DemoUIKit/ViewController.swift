//
//  ViewController.swift
//  DemoUIKit
//
//  Created by Juan Carlos on 12/27/25.
//

import UIKit

final class ComponentsViewController: UITableViewController {
  private static let demosSectionID = "section:demos"
  private static let categorySectionPrefix = "section:category:"

  private var query: String = "" {
    didSet { rebuildSections() }
  }

  private var sections: [ComponentsSectionModel] = []

  override func viewDidLoad() {
    super.viewDidLoad()

    title = "AIKit Elements"

    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    let searchController = UISearchController(searchResultsController: nil)
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchResultsUpdater = self
    searchController.searchBar.placeholder = "Search components"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false

    rebuildSections()
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    defer { tableView.deselectRow(at: indexPath, animated: true) }

    let row = sections[indexPath.section].rows[indexPath.row]

    switch row.kind {
    case .demo(let id):
      let vc: UIViewController
      switch id {
      case "demo/chat":
        vc = PlaceholderViewController(title: "Chat Demo", detail: "TODO: Port OpenRouterChatDemoView to UIKit demo.")
      case "settings/openrouter":
        vc = PlaceholderViewController(title: "Settings", detail: "TODO: Port OpenRouterSettingsView to UIKit demo.")
      default:
        vc = PlaceholderViewController(title: row.title, detail: "TODO")
      }
      navigationController?.pushViewController(vc, animated: true)

    case .component(let id):
      guard let component = ComponentCatalog.component(id: id) else { return }
      navigationController?.pushViewController(ComponentDetailViewController(component: component), animated: true)
    }
  }

  private func rebuildSections() {
    var newSections: [ComponentsSectionModel] = []

    let demos = [
      ComponentsRowModel(
        id: "demo/chat",
        title: "Chat Demo",
        summary: "Live OpenRouter chat using the current component set",
        kind: .demo(id: "demo/chat")
      ),
      ComponentsRowModel(
        id: "settings/openrouter",
        title: "Settings",
        summary: "Configure OpenRouter API key + model",
        kind: .demo(id: "settings/openrouter")
      ),
    ]
    newSections.append(.init(id: Self.demosSectionID, title: "Demos", rows: demos))

    for category in ComponentCategory.allCases {
      let components = ComponentCatalog.components(in: category, matching: query)
      guard components.isEmpty == false else { continue }
      let rows = components.map {
        ComponentsRowModel(
          id: $0.id,
          title: $0.name,
          summary: $0.summary,
          kind: .component(id: $0.id)
        )
      }
      newSections.append(.init(
        id: Self.categorySectionPrefix + category.rawValue,
        title: category.title,
        rows: rows
      ))
    }

    sections = newSections
    tableView.reloadData()
  }

  override func numberOfSections(in tableView: UITableView) -> Int {
    sections.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    sections[section].rows.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    let row = sections[indexPath.section].rows[indexPath.row]

    var configuration = UIListContentConfiguration.subtitleCell()
    configuration.textProperties.numberOfLines = 1
    configuration.secondaryTextProperties.numberOfLines = 2
    configuration.text = row.title
    configuration.secondaryText = row.summary
    cell.contentConfiguration = configuration
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    sections[section].title
  }
}

extension ComponentsViewController: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {
    query = searchController.searchBar.text ?? ""
  }
}
