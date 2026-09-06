import SwiftUI

/// OpenRouter's documented no-callback PKCE flow also works when a browser
/// cannot return to the app. No client secret or hosted callback is needed.
struct OpenRouterCodeConnectionView: View {
    let onConnected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var authorization = OpenRouterAuthorization()
    @State private var code = ""
    @State private var didOpenSignIn = false
    @State private var isExchanging = false
    @State private var errorMessage: String?
    @State private var exchangeTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionLabel("Connect your account", subtitle: "If sign in cannot return to Prompti, use an authorization code instead.")
                    PromptiSectionSurface {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("1. Sign in securely in your browser.").font(.headline)
                            Text("Approve Prompti, then copy the authorization code shown by OpenRouter.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Open secure sign in", systemImage: "arrow.up.right.square") {
                                authorization = OpenRouterAuthorization()
                                code = ""
                                errorMessage = nil
                                do {
                                    let url = try authorization.authorizationURL(manual: true)
                                    openURL(url) { accepted in didOpenSignIn = accepted }
                                } catch { errorMessage = error.localizedDescription }
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(isExchanging)
                        }
                    }
                    PromptiSectionSurface {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("2. Return here and paste the code.").font(.headline)
                            SecureField("Authorization code", text: $code)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .modifier(PromptiCredentialFieldModifier())
                                .disabled(isExchanging)
                            Button {
                                isExchanging = true
                                errorMessage = nil
                                exchangeTask = Task {
                                    defer { isExchanging = false }
                                    do {
                                        let key = try await authorization.exchange(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
                                        try Task.checkCancellation()
                                        onConnected(key)
                                        dismiss()
                                    } catch is CancellationError { return }
                                    catch { errorMessage = error.localizedDescription }
                                }
                            } label: {
                                HStack {
                                    if isExchanging { ProgressView().tint(.white) }
                                    Text("Connect and verify")
                                }
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            .disabled(isExchanging || !didOpenSignIn || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if let errorMessage {
                        InlineNotice(symbol: "info.circle", text: errorMessage)
                    }
                    Text("The code expires after 10 minutes. Keep this page open while you sign in.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(PromptiBackground())
            .navigationTitle("OpenRouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onDisappear { exchangeTask?.cancel() }
    }
}
