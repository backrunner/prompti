import AuthenticationServices
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
    @State private var authorization = OpenRouterOAuthSession()
    @State private var showCodeConnection = false
    @State private var showAdvanced = false

    private var appleStatus: AppleModelStatus { AppleModelCapability.status(for: languageCode) }
    private var hasCredential: Bool {
        !apiKey.isEmpty || dependencies.secureStore.readAPIKey(for: provider) != nil
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
            } else if provider.kind == .openRouterOAuth {
                oauthControls
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
                Text("Your destination, language and scenes go to your selected provider. Credentials stay on this device. Model usage may use account credits.")
                    .font(.footnote).foregroundStyle(Color.promptMuted)
            }
        }
        .onChange(of: provider.model) { _, _ in invalidate() }
        .onChange(of: provider.baseURL) { _, _ in apiKey = ""; invalidate() }
        .onChange(of: apiKey) { _, _ in invalidate() }
        .sheet(isPresented: $showCodeConnection) {
            OpenRouterCodeConnectionView { key in
                apiKey = key
                connect(needsAuthorization: false)
            }
        }
        .onDisappear { connectionTask?.cancel(); authorization.cancel() }
    }

    private var recommendations: [ModelRecommendation] { ProviderPreset.models(for: provider) }

    private var presetSelection: Binding<ProviderPreset> {
        Binding(get: { ProviderPreset.matching(provider) }, set: { preset in
            guard preset != ProviderPreset.matching(provider) else { return }
            provider = preset.configuration
            apiKey = ""
            status = nil
            isVerified = preset == .apple && appleStatus == .available
        })
    }

    private var modelSelector: some View {
        Menu {
            if provider.kind == .openRouterOAuth {
                Section("Popular fast models") {
                    modelOptions(recommendations.filter { $0.weeklyRequests != nil })
                }
                Section("More fast models · usage unavailable") {
                    modelOptions(recommendations.filter { $0.weeklyRequests == nil })
                }
            } else {
                modelOptions(recommendations)
            }
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
        .disabled(isBusy)
        .accessibilityIdentifier("model.selection")
    }

    private func modelOptions(_ models: [ModelRecommendation]) -> some View {
        ForEach(models) { model in
            Button { provider.model = model.id } label: {
                if let requests = model.weeklyRequests {
                    Text("\(model.name) · \(requests.formatted(.number.notation(.compactName))) requests/week")
                } else {
                    Text(model.name)
                }
            }
            .accessibilityIdentifier("model.option.\(model.id)")
        }
    }

    private var modelDisplayName: String {
        recommendations.first(where: { $0.id == provider.model })?.name ?? provider.model
    }

    private var oauthControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PromptiSymbolBadge(symbol: "point.3.connected.trianglepath.dotted")
                VStack(alignment: .leading, spacing: 3) {
                    Text("One account. More possibilities.").font(.headline)
                    Text("GPT, Claude, Gemini and more")
                        .font(.subheadline).foregroundStyle(Color.promptMuted)
                }
            }

            modelSelector
            VStack(alignment: .leading, spacing: 4) {
                Text("Ranked by weekly requests · \(ModelRecommendations.openRouter.asOf)")
                Text("Models without public request counts appear separately.")
                Link("Source: OpenRouter · CC BY 4.0", destination: URL(string: "https://openrouter.ai/rankings")!)
            }
            .font(.caption).foregroundStyle(Color.promptMuted)

            Button {
                connect(needsAuthorization: isVerified || !hasCredential)
            } label: {
                HStack(spacing: 8) {
                    if isBusy { ProgressView().tint(.promptOnAction) }
                    Label(isVerified ? "Reconnect OpenRouter" : (hasCredential ? "Verify model" : "Connect with OpenRouter"),
                          systemImage: isVerified ? "checkmark.shield.fill" : "arrow.up.right.square")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(isBusy || provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("model.connect")

            DisclosureGroup("More connection options", isExpanded: $showAdvanced) {
                VStack(spacing: 12) {
                    TextField("Model ID", text: $provider.model)
                        .modifier(PromptiCredentialFieldModifier())
                    SecureField("API key", text: $apiKey)
                        .modifier(PromptiCredentialFieldModifier())
                    Button("Connect using an authorization code") { showCodeConnection = true }
                        .buttonStyle(SecondaryActionButtonStyle())
                    Link("Manage OpenRouter account", destination: URL(string: "https://openrouter.ai/settings/credits")!)
                        .font(.footnote)
                    Button("Sign in to another account") { connect(needsAuthorization: true) }
                        .buttonStyle(SecondaryActionButtonStyle())
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.top, 12).disabled(isBusy)
            }
            .font(.subheadline)
        }
    }

    private var apiKeyControls: some View {
        VStack(spacing: 12) {
            TextField("Base URL", text: $provider.baseURL)
                .keyboardType(.URL).modifier(PromptiCredentialFieldModifier())
            if !recommendations.isEmpty { modelSelector }
            TextField("Model ID", text: $provider.model)
                .modifier(PromptiCredentialFieldModifier())
                .accessibilityIdentifier("model.customID")
            SecureField(hasCredential ? "Replace API key" : "API key", text: $apiKey)
                .modifier(PromptiCredentialFieldModifier())
            Button { connect(needsAuthorization: false) } label: {
                HStack {
                    if isBusy { ProgressView() }
                    Label(isVerified ? "Connection verified" : "Test connection",
                          systemImage: isVerified ? "checkmark.circle.fill" : "bolt.horizontal.circle")
                }
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(!hasCredential || provider.model.isEmpty)
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

    private func connect(needsAuthorization: Bool) {
        guard !isBusy else { return }
        isBusy = true
        isVerified = false
        status = nil
        connectionTask = Task { @MainActor in
            defer { isBusy = false }
            do {
                var candidate = apiKey.isEmpty ? dependencies.secureStore.readAPIKey(for: provider) : apiKey
                if needsAuthorization { candidate = try await authorization.connect() }
                try Task.checkCancellation()
                // Keep a newly authorized key in the draft so credit/model failures can
                // be retried without authorizing another key. Save only on Done/Start.
                if let candidate { apiKey = candidate }
                let support = try await dependencies.generation.probe(configuration: provider, apiKey: candidate)
                try Task.checkCancellation()
                provider.structuredOutputSupport = support
                isVerified = true
                status = String(localized: "Connected. Your model is ready.")
            } catch is CancellationError {
                return
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                status = String(localized: "Sign in cancelled. You can try again whenever you’re ready.")
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
