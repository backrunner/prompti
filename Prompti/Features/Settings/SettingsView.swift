import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var didLoad = false
    @State private var provider = ProviderConfiguration()
    @State private var apiKey = ""
    @State private var explanationLanguage = ExplanationLanguage.english
    @State private var difficulty = TrainingDifficulty.basic
    @State private var questionCount = 5
    @State private var speechRate: Float = 0.44
    @State private var showImportConfirmation = false
    @State private var showClearInventory = false
    @State private var isPreGenerationEnabled = false
    @State private var inventoryTarget = 3
    @State private var dailyPreparationLimit = 12
    @State private var preparationWiFiOnly = true
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var testSucceeded = false
    @State private var showCostWarning = false
    @State private var showDeleteKeyConfirmation = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Group {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    PromptiWordmark()
                    Text("Practice for your next conversation.")
                        .font(.subheadline).foregroundStyle(Color.promptMuted)
                }
                .padding(.vertical, 8)
            }
            Section("Model") {
                if didLoad { ModelConnectionView(provider: $provider, apiKey: $apiKey,
                    isBusy: $isTesting, isVerified: $testSucceeded,
                    languageCode: dependencies.settings.languageCode)
                    .padding(.vertical, 8) }
            }

            if let statusMessage { Section { Text(LocalizedStringKey(statusMessage)).font(.footnote).foregroundStyle(Color.promptMuted) } }

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
                Picker("Speech playback", selection: $speechRate) {
                    Text("Slow").tag(Float(0.34))
                    Text("Normal").tag(Float(0.44))
                    Text("Fast").tag(Float(0.52))
                }
                Stepper(value: $questionCount, in: 3...20) {
                    LabeledContent("Questions", value: "\(questionCount)")
                }
            }

            Section("Question inventory") {
                Toggle("Prepare questions in advance", isOn: Binding(
                    get: { isPreGenerationEnabled },
                    set: { enabled in
                        isPreGenerationEnabled = enabled
                        if enabled { showCostWarning = true }
                    }
                ))
                Text("When enabled, Prompti may call your model while the app is active. This can use extra tokens and create provider charges.")
                    .font(.footnote)
                    .foregroundStyle(Color.promptMuted)
                if isPreGenerationEnabled {
                    Stepper("Inventory target: \(inventoryTarget)", value: $inventoryTarget, in: 3...20)
                    Stepper("Daily preparation limit: \(dailyPreparationLimit)", value: $dailyPreparationLimit, in: 3...50)
                    Toggle("Prepare only on Wi-Fi", isOn: $preparationWiFiOnly)
                    Text("Preparation pauses in Low Power Mode, on low battery or a constrained connection. The daily limit resets at midnight UTC; failed or cancelled requests also use the limit.")
                        .font(.footnote).foregroundStyle(Color.promptMuted)
                }
            }

            Section("Model usage on this device") {
                LabeledContent("Recent requests", value: "\(dependencies.usage.entries.count)")
                LabeledContent("Reported input tokens", value: "\(dependencies.usage.reportedInputTokens)")
                LabeledContent("Reported output tokens", value: "\(dependencies.usage.reportedOutputTokens)")
                LabeledContent("Requests with unknown usage", value: "\(dependencies.usage.unknownUsageCount)")
                Text("Includes generation, reviews, speech feedback and connection tests for the most recent 1,000 requests. Failed requests and fallbacks count too. Missing token usage is unknown; provider billing is authoritative.")
                    .font(.footnote).foregroundStyle(Color.promptMuted)
                ForEach(dependencies.usage.entries.suffix(5).reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.model).font(.subheadline)
                        HStack {
                            Text(LocalizedStringKey(entry.operationTitle))
                            Text("·")
                            Text(LocalizedStringKey(entry.statusTitle))
                        }
                        .font(.caption).foregroundStyle(Color.promptMuted)
                        Text(entry.createdAt, style: .date).font(.caption).foregroundStyle(Color.promptMuted)
                    }
                }
            }

            Section {
                Button("Clear unused questions", role: .destructive) { showClearInventory = true }
                    .accessibilityIdentifier("settings.clearInventory")
                    .confirmationDialog("Clear unused questions and pause preparation?", isPresented: $showClearInventory, titleVisibility: .visible) {
                        Button("Clear unused questions", role: .destructive) {
                            dependencies.settings.isPreGenerationEnabled = false
                            isPreGenerationEnabled = false
                            do { try QuestionInventory.clearUnused(context: modelContext) }
                            catch { statusMessage = error.localizedDescription }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: { Text("Answered questions and learning history stay saved.") }
            }

            Section("Sync & privacy") {
                LabeledContent("Learning data") {
                    Text(LocalizedStringKey(persistenceLabel))
                }
                Text(LocalizedStringKey(dependencies.persistence.status)).font(.footnote)
                if let date = dependencies.persistence.lastSync {
                    LabeledContent("Last sync event") { Text(date, style: .relative) }
                }
                Button("Retry iCloud connection") { Task { await dependencies.persistence.refresh() } }
                if !dependencies.persistence.importSources.isEmpty {
                    Button("Import previous local data") { showImportConfirmation = true }
                        .accessibilityIdentifier("settings.importLocal")
                        .confirmationDialog("Import local learning data into this account?", isPresented: $showImportConfirmation, titleVisibility: .visible) {
                            Button("Import local data") { dependencies.persistence.importLocalData() }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Previous storage and signed-out learning data will be copied into the currently open account. It can sync to this iCloud account when available. Only import data that belongs here. Existing history and the original local copy stay saved.")
                        }
                }
                if let message = dependencies.persistence.importMessage { Text(message).font(.footnote) }
                LabeledContent("API keys", value: "This device only")
                Text(LocalizedStringKey(persistenceDetail))
                    .font(.footnote)
                    .foregroundStyle(Color.promptMuted)
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
            .listRowBackground(Color.promptSurface)
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
            || speechRate != dependencies.settings.speechRate
            || isPreGenerationEnabled != dependencies.settings.isPreGenerationEnabled
            || inventoryTarget != dependencies.settings.inventoryTarget
            || dailyPreparationLimit != dependencies.settings.dailyPreparationLimit
            || preparationWiFiOnly != dependencies.settings.preparationWiFiOnly
    }

    private var providerNeedsTest: Bool {
        provider.kind != .apple
            && (provider != dependencies.settings.provider || !apiKey.isEmpty)
    }

    private func loadSettings() {
        guard !didLoad else { return }
        provider = dependencies.settings.provider
        explanationLanguage = dependencies.settings.explanationLanguage
        difficulty = dependencies.settings.difficulty
        questionCount = dependencies.settings.questionCount
        speechRate = dependencies.settings.speechRate
        isPreGenerationEnabled = dependencies.settings.isPreGenerationEnabled
        inventoryTarget = dependencies.settings.inventoryTarget
        dailyPreparationLimit = dependencies.settings.dailyPreparationLimit
        preparationWiFiOnly = dependencies.settings.preparationWiFiOnly
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
            dependencies.settings.speechRate = speechRate
            dependencies.settings.isPreGenerationEnabled = isPreGenerationEnabled
            dependencies.settings.inventoryTarget = inventoryTarget
            dependencies.settings.dailyPreparationLimit = dailyPreparationLimit
            dependencies.settings.preparationWiFiOnly = preparationWiFiOnly
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
            "Learning data is saved on this device. Each iCloud account uses separate storage; signing in does not automatically import signed-out data. Keys never sync."
        }
    }
}
