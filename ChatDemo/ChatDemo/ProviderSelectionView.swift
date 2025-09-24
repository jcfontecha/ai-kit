//
//  ProviderSelectionView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ProviderSelectionView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    @Environment(\.dismiss) private var dismiss
    @State private var modelDraft: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                providerSection
                modelSection
                if providerStore.isUsingRealAPI == false {
                    Section {
                        Text("Requests will use the mock provider until the selected provider is configured with valid API credentials.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .navigationTitle("AI Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyModelDraft()
                        dismiss()
                    }
                }
            }
        }
        .onAppear(perform: syncModelDraft)
        .onChange(of: providerStore.selection.provider) { _ in
            syncModelDraft()
        }
    }
    
    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: providerBinding) {
                ForEach(ProviderStore.ProviderKind.allCases) { kind in
                    HStack {
                        Text(kind.displayName)
                        Spacer()
                        if let message = providerStore.availabilityMessage(for: kind) {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .tag(kind)
                }
            }
            .pickerStyle(.inline)
        }
    }
    
    private var modelSection: some View {
        Section("Model") {
            let models = providerStore.suggestedModels(for: providerStore.selection.provider)
            if models.isEmpty == false {
                ForEach(models, id: \.self) { model in
                    Button {
                        modelDraft = model
                        providerStore.setModel(model)
                    } label: {
                        HStack {
                            Text(model)
                            Spacer()
                            if modelDraft == model {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            TextField("Custom model identifier", text: $modelDraft)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onSubmit(applyModelDraft)
        }
    }
    
    private var providerBinding: Binding<ProviderStore.ProviderKind> {
        Binding(
            get: { providerStore.selection.provider },
            set: { newValue in
                providerStore.selectProvider(newValue)
                syncModelDraft()
            }
        )
    }
    
    private func syncModelDraft() {
        let current = providerStore.selection.modelId
        if current.isEmpty {
            modelDraft = providerStore.entries[providerStore.selection.provider]?.defaultModel ?? ""
        } else {
            modelDraft = current
        }
    }
    
    private func applyModelDraft() {
        let cleaned = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else {
            providerStore.setModel("")
            return
        }
        providerStore.setModel(cleaned)
    }
}
