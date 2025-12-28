struct ComponentsSectionModel {
  let id: String
  let title: String
  let rows: [ComponentsRowModel]
}

struct ComponentsRowModel {
  enum Kind {
    case demo(id: String)
    case component(id: ComponentID)
  }

  let id: String
  let title: String
  let summary: String
  let kind: Kind
}
