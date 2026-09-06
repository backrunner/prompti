import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var didLoad = false
    @State private var provider = ProviderConfiguration()
    @State private var apiKey = ""
    @State private var explanationLanguage = ExplanationLanguage.english
    @State private var difficulty = TrainingDifficulty.basic
    @State private var questionCount = 5
    @State private var isPreGenerationEnabled = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var testSucceeded = false
    @State private var showCostWarning = false
    @State private var showDeleteKeyConfirmation = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Model") {
                if didLoad { ModelConnectionView(provider: $provider, apiKey: $apiKey,
                    isBusy: $isTesting, isVerified: $testSucceeded,
                    languageCode: dependencies.settings.languageCode)
                    .padding(.vertical, 8) }
            }

            if let statusMessage { Section { Text(LocalizedStringKey(statusMessage)).font(.footnote).foregroundStyle(.secondary) } }

            Section("Practice defaults") {
                Picker("Explanations", selection: $explanationLanguage) {
                    ForEach(ExplanationLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.title)).tag(language)
                    }
                }
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(TrainingDifficulty.allCases) { difficulty in
                        Text(LocalizedStringKey(difficulty.title)).tag(difficulty)
                    }
                }
                Stepper(value: $questionCount, in: 3...20) {
                    LabeledContent("Questions", value: "\(questionCount)")
                }
            }

            Section("Question inventory") {
                Toggle("Prepare questions in advance", isOn: $isPreGenerationEnabled)
                    .onChange(of: isPreGenerationEnabled) { _, enabled in
                        if enabled { showCostWarning = true }
                    }
                Text("When enabled, Prompti may call your model while the app is active. This can use extra tokens and create provider charges.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Sync & privacy") {
                LabeledContent("Learning data") {
                    Text(LocalizedStringKey(persistenceLabel))
                }
                LabeledContent("API keys", value: "This device only")
                Text(LocalizedStringKey(persistenceDetail))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Run setup again") {
                    showResetConfirmation = true
                }
                .confirmationDialog("Run setup again?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                    Button("Run setup again") {
                        dependencies.settings.resetOnboarding()
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Your learning history stays saved. You will choose the destination, language and model again.")
                }
                Button("Disconnect this model", role: .destructive) {
                    showDeleteKeyConfirmation = true
                }
                .confirmationDialog("Delete the API key from this device?", isPresented: $showDeleteKeyConfirmation, titleVisibility: .visible) {
                    Button("Disconnect this model", role: .destructive) {
                        dependencies.secureStore.deleteAPIKey(for: provider)
                        apiKey = ""
                        testSucceeded = false
                        statusMessage = "Disconnected on this device. You can revoke the key in your provider account."
                    }
                    Button("Cancel", role: .cancel) { }
                }
            }
            .disabled(isTesting)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(isTesting)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: saveAndDismiss)
                .disabled(isTesting || (providerNeedsTest && !testSucceeded))
                .accessibilityIdentifier("settings.done")
            }
        }
        .onAppear(perform: loadSettings)
        .interactiveDismissDisabled(isTesting || hasUnsavedChanges)
        .scrollContentBackground(.hidden)
        .background(PromptiBackground())
        .accessibilityIdentifier("settings.root")
        .sensoryFeedback(.selection, trigger: provider.kind)
        .sensoryFeedback(.success, trigger: testSucceeded)
        .alert("Extra model usage", isPresented: $showCostWarning) {
            Button("Keep enabled") { }
            Button("Turn off", role: .cancel) { isPreGenerationEnabled = false }
        } message: {
            Text("Preparing questions before you ask for them can consume additional tokens and may create charges from your model provider.")
        }
    }

    private var hasUnsavedChanges: Bool {
        provider != dependencies.settings.provider || !apiKey.isEmpty
            || explanationLanguage != dependencies.settings.explanationLanguage
            || difficulty != dependencies.settings.difficulty
            || questionCount != dependencies.settings.questionCount
            || isPreGenerationEnabled != dependencies.settings.isPreGenerationEnabled
    }

    private var providerNeedsTest: Bool {
        provider.kind != .apple
            && (provider != dependencies.settings.provider || !apiKey.isEmpty)
    }

    private func loadSettings() {
        provider = dependencies.settings.provider
        explanationLanguage = dependencies.settings.explanationLanguage
        difficulty = dependencies.settings.difficulty
        questionCount = dependencies.settings.questionCount
        isPreGenerationEnabled = dependencies.settings.isPreGenerationEnabled
        didLoad = true
        testSucceeded = provider.kind == .apple || (provider.structuredOutputSupport != .unknown && dependencies.secureStore.readAPIKey(for: provider) != nil)
    }

    private func saveAndDismiss() {
        do {
            if !apiKey.isEmpty {
                try dependencies.secureStore.saveAPIKey(apiKey, for: provider)
            }
            dependencies.settings.provider = provider
            dependencies.settings.explanationLanguage = explanationLanguage
            dependencies.settings.difficulty = difficulty
            dependencies.settings.questionCount = questionCount
            dependencies.settings.isPreGenerationEnabled = isPreGenerationEnabled
            dismiss()
        } catch {
            testSucceeded = false
            statusMessage = error.localizedDescription
        }
    }

    private var persistenceLabel: String {
        switch dependencies.persistenceMode {
        case .iCloud: "iCloud private database"
        case .localFallback: "On this device"
        }
    }

    private var persistenceDetail: String {
        switch dependencies.persistenceMode {
        case .iCloud:
            "Questions, attempts and progress use your private iCloud database. Keys never sync."
        case .localFallback:
            "iCloud storage was unavailable when Prompti started, so learning data is being kept locally on this device. Keys never sync."
        }
    }
}
