import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case destination
    case language
    case model
    case preferences

    var accessibilityIdentifier: String {
        switch self {
        case .welcome: "onboarding.welcome"
        case .destination: "onboarding.destination"
        case .language: "onboarding.language"
        case .model: "onboarding.model"
        case .preferences: "onboarding.preferences"
        }
    }
}

struct OnboardingView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step: OnboardingStep = .welcome
    @State private var destinationID = "tokyo"
    @State private var languageCode = "ja"
    @State private var provider = ProviderConfiguration(kind: .openRouterOAuth, baseURL: ProviderKind.openRouterOAuth.defaultBaseURL, model: ProviderKind.openRouterOAuth.defaultModel)
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var testSucceeded = false
    @State private var showDestinationPicker = false
    @State private var customDestination: Destination?
    @State private var landingVisible = false
    @State private var difficulty = TrainingDifficulty.basic
    @State private var questionCount = 5
    @State private var enablePreparation = false
    @State private var explanationLanguage = ExplanationLanguage.english
    @State private var stepMovesForward = true

    private var destination: Destination {
        if let customDestination, customDestination.id == destinationID { return customDestination }
        return dependencies.catalog.destination(id: destinationID)
    }
    private var appleStatus: AppleModelStatus { AppleModelCapability.status(for: languageCode) }

    var body: some View {
        ZStack {
            PromptiBackground()
            VStack(spacing: 0) {
                if step != .welcome {
                    progress
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                }

                Group {
                    switch step {
                    case .welcome: welcome
                    case .destination: destinationPicker
                    case .language: languagePicker
                    case .model: modelPicker
                    case .preferences: preferencesPicker
                    }
                }
                .id(step)
                .accessibilityIdentifier(step.accessibilityIdentifier)
                .transition(stepTransition)
                .animation(reduceMotion ? .easeOut(duration: 0.18) : .smooth(duration: 0.24), value: step)

                controls
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .background(PromptiActionScrim())
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled(isTesting)
        .sheet(isPresented: $showDestinationPicker) {
            DestinationPickerView(selection: destinationSelection)
        }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.selection, trigger: provider.kind)
        .onChange(of: destinationID) { _, _ in
            if !destination.languages.contains(where: { $0.code == languageCode }) {
                languageCode = destination.languages[0].code
            }
        }
        .onChange(of: languageCode) { _, _ in
            testSucceeded = false
            if appleStatus == .available {
                provider = ProviderConfiguration(kind: .apple, baseURL: "", model: "system", structuredOutputSupport: .supported)
            } else if provider.kind == .apple {
                provider = ProviderConfiguration(kind: .openRouterOAuth, baseURL: ProviderKind.openRouterOAuth.defaultBaseURL, model: ProviderKind.openRouterOAuth.defaultModel)
            }
        }

    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases.filter { $0 != .welcome }, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.promptAccent : Color.promptMuted.opacity(0.2))
                    .frame(height: 5)
            }
        }
        .accessibilityLabel(Text("Step \(step.rawValue) of \(OnboardingStep.allCases.count - 1)"))
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: stepMovesForward ? .trailing : .leading))
    }

    private var welcome: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PromptiWordmark()

                    Spacer(minLength: 8)

                    LandingConversationVisual()
                        .scaleEffect(landingVisible ? 1 : 0.96)
                        .opacity(landingVisible ? 1 : 0)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: landingVisible)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Say hello to the world.")
                            .font(PromptiTypography.hero)
                            .fontDesign(.rounded)
                        Text("Fast practice for any destination.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.promptMuted)
                    }
                    .offset(y: landingVisible ? 0 : 12)
                    .opacity(landingVisible ? 1 : 0)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.7).delay(0.08), value: landingVisible)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            LandingFeature(symbol: "mappin.and.ellipse", title: "Any destination", tint: .promptAccent)
                            LandingFeature(symbol: "character.bubble.fill", title: "中文 + English", tint: .promptAccent)
                        }
                        VStack(spacing: 10) {
                            LandingFeature(symbol: "mappin.and.ellipse", title: "Any destination", tint: .promptAccent)
                            LandingFeature(symbol: "character.bubble.fill", title: "中文 + English", tint: .promptAccent)
                        }
                    }
                    .offset(y: landingVisible ? 0 : 10)
                    .opacity(landingVisible ? 1 : 0)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.7).delay(0.16), value: landingVisible)

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(minHeight: max(proxy.size.height - 24, 0), alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            landingVisible = true
        }
    }

    private var destinationPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionLabel("Pick your next stop")

                Button {
                    showDestinationPicker = true
                } label: {
                    DestinationSummaryCard(destination: destination, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.chooseDestination")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        OnboardingFact(value: "\(destination.languages.count)", label: "languages", symbol: "character.bubble.fill", tint: .promptAccent)
                        OnboardingFact(value: "\(destination.localScenes.count)", label: "local picks", symbol: "mappin.and.ellipse", tint: .promptAccent)
                    }
                    VStack(spacing: 10) {
                        OnboardingFact(value: "\(destination.languages.count)", label: "languages", symbol: "character.bubble.fill", tint: .promptAccent)
                        OnboardingFact(value: "\(destination.localScenes.count)", label: "local picks", symbol: "mappin.and.ellipse", tint: .promptAccent)
                    }
                }

                Label(destination.landmarkName, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(onboardingAccent)
                    .padding(.horizontal, 4)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var languagePicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionLabel("Choose your language", subtitle: "You can change it for every practice set.")
                DestinationSummaryCard(destination: destination, compact: true)
                VStack(spacing: 8) {
                    ForEach(destination.languages) { language in
                        Button {
                            languageCode = language.code
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language.localName).font(.headline)
                                    Text(language.name).font(.caption).foregroundStyle(Color.promptMuted)
                                }
                                Spacer()
                                Image(systemName: language.code == languageCode ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(language.code == languageCode ? onboardingAccent : Color.promptMuted)
                            }
                            .padding(16)
                            .background(
                                language.code == languageCode ? Color.promptSelection : Color.promptSurface,
                                in: RoundedRectangle(cornerRadius: PromptiRadius.surface)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(Text(language.code == languageCode ? "Selected" : "Not selected"))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var modelPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionLabel("Choose your AI", subtitle: "Connect an account, or use your own API key.")
                PromptiSectionSurface {
                    ModelConnectionView(provider: $provider, apiKey: $apiKey,
                        isBusy: $isTesting, isVerified: $testSucceeded, languageCode: languageCode)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if appleStatus == .available, provider.structuredOutputSupport == .unknown, apiKey.isEmpty {
                provider = ProviderConfiguration(kind: .apple, baseURL: "", model: "system", structuredOutputSupport: .supported)
                testSucceeded = true
            }
        }
    }

    private var preferencesPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionLabel("Set your pace", subtitle: "These defaults can be changed for every practice set.")

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Difficulty", subtitle: difficulty.detail)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) {
                            ForEach(TrainingDifficulty.allCases) { item in
                                Button {
                                    difficulty = item
                                } label: {
                                    HStack {
                                        Text(LocalizedStringKey(item.title))
                                        Spacer()
                                        Image(systemName: item == difficulty ? "checkmark.circle.fill" : "circle")
                                    }
                                    .padding(12)
                                    .background(Color.promptMuted.opacity(0.08), in: .rect(cornerRadius: PromptiRadius.control))
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(Text(item == difficulty ? "Selected" : "Not selected"))
                            }
                        }
                    } else {
                        Picker("Difficulty", selection: $difficulty) {
                            ForEach(TrainingDifficulty.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Stepper(value: $questionCount, in: 3...20) {
                    LabeledContent("Default set") {
                        Text("\(questionCount) questions")
                    }
                }

                Picker("Explanations", selection: $explanationLanguage) {
                    ForEach(ExplanationLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.title)).tag(language)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Prepare questions in advance", isOn: $enablePreparation)
                    Text("When enabled, Prompti may call your selected model while the app is open. This can use extra tokens and create provider charges.")
                        .font(.footnote)
                        .foregroundStyle(Color.promptMuted)
                }

                if let errorMessage { InlineNotice(symbol: "exclamationmark.triangle", text: errorMessage, tone: .error) }

                InlineNotice(
                    symbol: "hand.raised.fill",
                    text: "Skipped, reported and uncertain spoken answers never reduce your accuracy."
                )
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var controls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                controlButtons
            }
        } else {
            controlButtons
        }
    }

    private var controlButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                backButton
                continueButton
            }
            VStack(spacing: 10) {
                continueButton
                backButton
            }
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if step != .welcome {
            Button("Back", systemImage: "chevron.left") {
                if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                    stepMovesForward = false
                    step = previous
                }
            }
            .buttonStyle(CompactGlassButtonStyle())
            .accessibilityIdentifier("onboarding.back")
            .disabled(isTesting)
        }
    }

    private var continueButton: some View {
        Button {
            advance()
        } label: {
            Label(
                step == .preferences ? "Start learning" : (step == .welcome ? "Let’s get started" : "Continue"),
                systemImage: step == .preferences ? "bubble.left.and.bubble.right" : "arrow.right"
            )
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(isTesting || (step == .model && !canFinish))
        .accessibilityIdentifier("onboarding.continue")
    }

    private var onboardingAccent: Color {
        .promptAccent
    }

    private var canFinish: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-demo") { return true }
        #endif
        return provider.kind == .apple ? appleStatus == .available : testSucceeded
    }

    private func advance() {
        if step == .preferences {
            do {
                if provider.kind != .apple, !apiKey.isEmpty { try dependencies.secureStore.saveAPIKey(apiKey, for: provider) }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            dependencies.settings.destinationID = destinationID
            dependencies.settings.customDestination = customDestination
            dependencies.settings.languageCode = languageCode
            dependencies.settings.explanationLanguage = explanationLanguage
            dependencies.settings.provider = provider
            dependencies.settings.difficulty = difficulty
            dependencies.settings.questionCount = questionCount
            dependencies.settings.isPreGenerationEnabled = enablePreparation
            dependencies.settings.hasCompletedOnboarding = true
            return
        }
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            stepMovesForward = true
            step = next
        }
    }

    private var destinationSelection: Binding<Destination> {
        Binding(
            get: { destination },
            set: { newValue in
                destinationID = newValue.id
                customDestination = dependencies.catalog.contains(id: newValue.id) ? nil : newValue
            }
        )
    }


}

private struct LandingFeature: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.promptSurface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.promptBorder, lineWidth: 0.75)
        }
    }
}

private struct OnboardingFact: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(PromptiTypography.section).fontDesign(.rounded)
                Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Color.promptMuted)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .promptiSurface(radius: PromptiRadius.control)
    }
}
