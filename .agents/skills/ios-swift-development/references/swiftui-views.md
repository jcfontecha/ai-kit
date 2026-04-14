# SwiftUI Views

## SwiftUI Views

Repo note: prefer feature-specific names, Observation, and modern navigation APIs that fit the app. Avoid `ContentView` and `ObservableObject`-based examples as defaults in this repo.

```swift
struct MainView: View {
  @State private var userModel = UserModel()

  var body: some View {
    TabView {
      HomeView()
        .tabItem { Label("Home", systemImage: "house") }

      ProfileView(model: userModel)
        .tabItem { Label("Profile", systemImage: "person") }
    }
  }
}

struct HomeView: View {
  @State private var items: [Item] = []
  @State private var loading = true

  var body: some View {
    NavigationStack {
      ZStack {
        if loading {
          ProgressView()
        } else {
          List(items) { item in
            NavigationLink(destination: ItemDetailView(item: item)) {
              VStack(alignment: .leading) {
                Text(item.title).font(.headline)
                Text(item.description).font(.subheadline).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .navigationTitle("Items")
      .task {
        await loadItems()
      }
    }
  }

  private func loadItems() async {
    do {
      items = try await NetworkService.shared.fetch([Item].self, from: "/items")
    } catch {
      print("Error: \(error)")
    }
    loading = false
  }
}

struct ItemDetailView: View {
  let item: Item
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(item.title).font(.title2).fontWeight(.bold)
        Text(item.description).font(.body)
        Text("Price: $\(String(format: "%.2f", item.price))")
          .font(.headline).foregroundStyle(.blue)
        Spacer()
      }
      .padding()
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct ProfileView: View {
  let model: UserModel

  var body: some View {
    NavigationStack {
      ZStack {
        if model.isLoading {
          ProgressView()
        } else if let user = model.user {
          VStack(spacing: 20) {
            Text(user.name).font(.title).fontWeight(.bold)
            Text(user.email).font(.subheadline)
            Button("Logout") { model.logout() }
              .foregroundStyle(.red)
            Spacer()
          }
          .padding()
        } else {
          Text("No profile data")
        }
      }
      .navigationTitle("Profile")
      .task {
        await model.fetchUser(id: UUID())
      }
    }
  }
}

struct Item: Codable, Identifiable {
  let id: String
  let title: String
  let description: String
  let price: Double
}
```
