import SwiftUI

struct OpenRouterSettingsView: View {
  @AppStorage(AppSettings.openRouterAPIKeyKey) private var apiKey: String = ""
  @AppStorage(AppSettings.openRouterModelIDKey) private var modelID: String = AppSettings.defaultOpenRouterModelID

  @State private var showKey: Bool = false

  var body: some View {
    Form {
      Section("OpenRouter") {
        if showKey {
          TextField("API Key", text: $apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } else {
          SecureField("API Key", text: $apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }

        Toggle("Show API key", isOn: $showKey)

        TextField("Model ID", text: $modelID)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()

        Text("Keys are stored in UserDefaults (insecure). This is fine for a demo app.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Button("Clear API Key", role: .destructive) { apiKey = "" }
        Button("Reset Model ID") { modelID = AppSettings.defaultOpenRouterModelID }
      }
    }
    .navigationTitle("Settings")
  }
}
