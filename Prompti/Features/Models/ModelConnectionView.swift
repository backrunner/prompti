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
            Picker("Connection", selection: $provider.kind) {
                if appleStatus == .available {
                    Text("Apple On-Device").tag(ProviderKind.apple)
                }
                Text("OpenRouter · Sign in").tag(ProviderKind.openRouterOAuth)
                Text("OpenAI Responses").tag(ProviderKind.openAIResponses)
                Text("OpenAI Chat / Compatible").tag(ProviderKind.openAIChat)
                Text("Anthropic Messages").tag(ProviderKind.anthropic)
            }
            .pickerStyle(.menu)
            .disabled(isBusy)
            .accessibilityIdentifier("model.provider")
            .onChange(of: provider.kind) { _, kind in
                provider = ProviderConfiguration(kind: kind, baseURL: kind.defaultBaseURL, model: kind.defaultModel,
                    structuredOutputSupport: kind == .apple ? .supported : .unknown)
                apiKey = ""
                status = nil
                isVerified = kind == .apple
            }

            if provider.kind == .apple {
                Label("Private and on-device", systemImage: "apple.intelligence")
                    .font(.headline)
                Text("Exercises are generated on this device. Prompti still checks every question before showing it.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if provider.kind == .openRouterOAuth {
                oauthControls
            } else {
                apiKeyControls
            }

            if let status {
                Label(LocalizedStringKey(status), systemImage: isVerified ? "checkmark.circle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(isVerified ? Color.promptAccent : Color.secondary)
                    .accessibilityIdentifier("model.status")
            }

            if provider.kind != .apple {
                Text("Your destination, language and scenes go to your selected provider. Credentials stay on this device. Model usage may use account credits.")
                    .font(.footnote).foregroundStyle(.secondary)
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

    private var modelDisplayName: String {
        switch provider.model {
        case "openai/gpt-5-mini": "GPT 5 mini"
        case "anthropic/claude-sonnet-4.5": "Claude Sonnet 4.5"
        case "google/gemini-2.5-flash": "Gemini 2.5 Flash"
        default: provider.model
        }
    }

    private var oauthControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2).foregroundStyle(Color.promptAccent)
                    .frame(width: 48, height: 48)
                    .background(Color.promptMint.opacity(0.2), in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text("One account. More possibilities.").font(.headline)
                    Text("GPT, Claude, Gemini and more")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Menu {
                Button("GPT 5 mini") { provider.model = "openai/gpt-5-mini" }
                Button("Claude Sonnet 4.5") { provider.model = "anthropic/claude-sonnet-4.5" }
                Button("Gemini 2.5 Flash") { provider.model = "google/gemini-2.5-flash" }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Model").font(.caption).foregroundStyle(.secondary)
                        Text(modelDisplayName).font(.subheadline.weight(.medium)).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption.bold())
                }
                .padding(14)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: PromptiRadius.control))
            }
            .foregroundStyle(.primary)
            .disabled(isBusy)
            .accessibilityIdentifier("model.selection")

            Button {
                connect(needsAuthorization: isVerified || !hasCredential)
            } label: {
                HStack(spacing: 8) {
                    if isBusy { ProgressView().tint(.white) }
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
            TextField("Model ID", text: $provider.model)
                .modifier(PromptiCredentialFieldModifier())
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
                status = "Connected. Your model is ready."
            } catch is CancellationError {
                return
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                status = "Sign in cancelled. You can try again whenever you’re ready."
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
