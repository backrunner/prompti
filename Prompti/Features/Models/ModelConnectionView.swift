import SwiftUI

/// Shared by setup and settings. A connection is only ready after this exact
/// provider/model/credential combination has completed the capability probe.
struct ModelConnectionView: View {
    @Binding var provider: ProviderConfiguration
    @Binding var apiKey: String
    @Binding var isBusy: Bool
    @Binding var isVerified: Bool
    let languageCode: String

    @Environment(AppDependencies.self) private var dependencies
    @State private var status: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var showAdvanced = false
    @State private var isEnteringModel = false

    private var appleStatus: AppleModelStatus { AppleModelCapability.status(for: languageCode) }
    private var hasCredential: Bool {
        apiKey.isEmpty
            ? dependencies.secureStore.readAPIKey(for: provider) != nil
            : !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var recommendations: [ModelRecommendation] { ProviderPreset.models(for: provider) }
    private var needsEndpointField: Bool {
        ProviderPreset.matching(provider) == .compatible || recommendations.isEmpty
    }
    private var needsModelField: Bool {
        isEnteringModel || !recommendations.contains { $0.id == provider.model }
    }
    private var canConnect: Bool {
        hasCredential && !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Connection", selection: presetSelection) {
                ForEach(ProviderPreset.allCases.filter { $0 != .apple || appleStatus == .available }) { preset in
                    Text(LocalizedStringKey(preset.title)).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .disabled(isBusy)
            .accessibilityIdentifier("model.provider")

            if provider.kind == .apple {
                Label("Private and on-device", systemImage: "apple.intelligence")
                    .font(.headline)
                Text("Exercises are generated on this device. Prompti still checks every question before showing it.")
                    .font(.footnote).foregroundStyle(Color.promptMuted)
            } else {
                apiKeyControls
            }

            if let status {
                Label(status, systemImage: isVerified ? "checkmark.circle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(isVerified ? Color.promptSuccess : Color.promptMuted)
                    .accessibilityIdentifier("model.status")
            }

            if provider.kind != .apple {
                Text("Your provider processes exercise data and may charge for usage.")
                    .font(.footnote).foregroundStyle(Color.promptMuted)
            }
        }
        .onChange(of: provider.model) { _, _ in invalidate() }
        .onChange(of: provider.baseURL) { _, _ in apiKey = ""; invalidate() }
        .onChange(of: apiKey) { _, _ in invalidate() }
        .onDisappear { connectionTask?.cancel() }
    }

    private var presetSelection: Binding<ProviderPreset> {
        Binding(get: { ProviderPreset.matching(provider) }, set: { preset in
            guard preset != ProviderPreset.matching(provider) else { return }
            provider = preset.configuration
            apiKey = ""
            status = nil
            isEnteringModel = false
            showAdvanced = false
            isVerified = preset == .apple && appleStatus == .available
        })
    }

    private var modelSelector: some View {
        Menu {
            ForEach(recommendations) { model in
                Button {
                    isEnteringModel = false
                    provider.model = model.id
                } label: {
                    Text(model.name)
                }
                .accessibilityIdentifier("model.option.\(model.id)")
            }
            Button("Enter model ID") {
                isEnteringModel = true
                provider.model = ""
            }
            .accessibilityIdentifier("model.enterID")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Model").font(.caption).foregroundStyle(Color.promptMuted)
                    Text(modelDisplayName).font(.subheadline.weight(.medium)).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption.bold())
            }
            .padding(14)
            .background(Color.promptSurfaceRaised, in: .rect(cornerRadius: PromptiRadius.control))
        }
        .foregroundStyle(Color.promptText)
        .accessibilityIdentifier("model.selection")
    }

    private var modelDisplayName: String {
        if provider.model.isEmpty { return String(localized: "Custom model") }
        return recommendations.first(where: { $0.id == provider.model })?.name ?? provider.model
    }

    private var endpointField: some View {
        TextField("Base URL", text: $provider.baseURL)
            .keyboardType(.URL).modifier(PromptiCredentialFieldModifier())
            .accessibilityIdentifier("model.endpoint")
    }

    private var apiKeyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if needsEndpointField { endpointField }
            SecureField(hasCredential ? "Replace API key" : "API key", text: $apiKey)
                .modifier(PromptiCredentialFieldModifier())
                .accessibilityIdentifier("model.apiKey")
            if !recommendations.isEmpty { modelSelector }
            if needsModelField {
                TextField("Model ID", text: $provider.model)
                    .modifier(PromptiCredentialFieldModifier())
                    .accessibilityIdentifier("model.customID")
            }
            Button { connect() } label: {
                HStack {
                    if isBusy { ProgressView().tint(.promptOnAction) }
                    Label(isVerified ? "Connection verified" : "Test connection",
                          systemImage: isVerified ? "checkmark.circle.fill" : "bolt.horizontal.circle")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(!canConnect)
            .accessibilityIdentifier("model.connect")

            DisclosureGroup("More connection options", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    if !needsEndpointField && provider.kind != .openRouter { endpointField }
                    if provider.kind == .openRouter {
                        Link("Get an OpenRouter API key", destination: URL(string: "https://openrouter.ai/keys")!)
                        Link("Source: OpenRouter · CC BY 4.0", destination: URL(string: "https://openrouter.ai/rankings")!)
                    }
                    Text("Your destination, language and scenes go to your selected provider. Credentials stay on this device. Model usage may use account credits.")
                }
                .font(.footnote).foregroundStyle(Color.promptMuted)
                .padding(.top, 12)
            }
            .font(.subheadline)
            .accessibilityIdentifier("model.advanced")
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .disabled(isBusy)
    }

    private func invalidate() {
        guard !isBusy else { return }
        provider.structuredOutputSupport = provider.kind == .apple ? .supported : .unknown
        isVerified = provider.kind == .apple && appleStatus == .available
        status = nil
    }

    private func connect() {
        guard !isBusy, canConnect else { return }
        isBusy = true
        isVerified = false
        status = nil
        connectionTask = Task { @MainActor in
            defer { isBusy = false }
            do {
                let candidate = apiKey.isEmpty ? dependencies.secureStore.readAPIKey(for: provider)
                    : apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                // Keep the tested key in the draft. Save only on Done/Start.
                if let candidate { apiKey = candidate }
                let support = try await dependencies.generation.probe(configuration: provider, apiKey: candidate)
                try Task.checkCancellation()
                provider.structuredOutputSupport = support
                isVerified = true
                status = String(localized: "Connected. Your model is ready.")
            } catch is CancellationError {
                return
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
