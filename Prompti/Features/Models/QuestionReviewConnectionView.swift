import SwiftUI

struct QuestionReviewConnectionView: View {
    @Binding var mode: QuestionReviewMode
    @Binding var apiKey: String
    @Binding var isBusy: Bool
    @Binding var isVerified: Bool
    @Binding var removeSavedKey: Bool
    let hasSavedKey: Bool

    @Environment(AppDependencies.self) private var dependencies
    @FocusState private var keyIsFocused: Bool
    @State private var status: String?
    @State private var connectionTask: Task<Void, Never>?

    private var hasCredential: Bool {
        if !apiKey.isEmpty { return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasSavedKey && !removeSavedKey
    }

    var body: some View {
        Section {
            Picker("Review with", selection: $mode) {
                ForEach(QuestionReviewMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.title)).tag(mode)
                }
            }
            .disabled(isBusy)
            .accessibilityIdentifier("review.provider")

            if mode == .typeSafeJev {
                VStack(alignment: .leading, spacing: PromptiSpacing.related) {
                    HStack {
                        Text("TypeSafe API key")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Link("Get API key", destination: URL(string: "https://console.typesafe.ai")!)
                            .font(.subheadline)
                            .frame(minHeight: 44)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.promptAction)
                            .accessibilityIdentifier("review.getKey")
                    }
                    SecureField(hasSavedKey && !removeSavedKey ? "Replace API key" : "Paste API key", text: $apiKey)
                        .modifier(PromptiCredentialFieldModifier())
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($keyIsFocused)
                        .submitLabel(.done)
                        .onSubmit { keyIsFocused = false }
                        .disabled(isBusy)
                        .accessibilityIdentifier("review.apiKey")
                    PromptiConnectionTestRow(isBusy: isBusy, isVerified: isVerified,
                        canTest: hasCredential, error: status,
                        actionID: "review.test", statusID: "review.status", action: connect)
                }
                .padding(.vertical, PromptiSpacing.inline)

                DisclosureGroup("Review details") {
                    VStack(alignment: .leading, spacing: PromptiSpacing.related) {
                        Text("Jev checks each question. Uncertain results are reviewed by your generation model; connection failures stop preparation.")
                        Text("Jev works best in English. Review quality in other languages needs validation.")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.promptMuted)
                    .padding(.vertical, PromptiSpacing.inline)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("review.detailsContent")
                }
                .font(.subheadline)
                .tint(Color.promptMuted)
                .accessibilityIdentifier("review.details")

                if hasSavedKey && !removeSavedKey {
                    Button("Remove TypeSafe key", role: .destructive) {
                        removeSavedKey = true
                        apiKey = ""
                        isVerified = false
                        status = nil
                        mode = .generationModel
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.promptError)
                    .disabled(isBusy)
                    .accessibilityIdentifier("review.removeKey")
                }
            }
        } header: {
            Text("Question review")
        } footer: {
            if mode == .typeSafeJev {
                Text("TypeSafe receives exercise content. Reviews and connection tests may incur charges. Your key stays on this device.")
                    .foregroundStyle(Color.promptMuted)
            }
        }
        .onChange(of: apiKey) { _, _ in
            isVerified = false
            status = nil
        }
        .onDisappear {
            connectionTask?.cancel()
        }
    }

    private func connect() {
        keyIsFocused = false
        guard hasCredential, !isBusy else { return }
        isBusy = true
        isVerified = false
        status = nil
        let candidate = apiKey.isEmpty && !removeSavedKey ? dependencies.secureStore.readReviewKey()
            : apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // The exact tested draft is retained, never persisted before Settings Done.
        connectionTask = Task { @MainActor in
            defer { isBusy = false }
            do {
                guard let candidate, !candidate.isEmpty else { throw TypeSafeReviewError.missingKey }
                try await dependencies.generation.probeReview(apiKey: candidate)
                try Task.checkCancellation()
                isVerified = true
                status = nil
            } catch is CancellationError { }
            catch { status = error.localizedDescription }
        }
    }
}
