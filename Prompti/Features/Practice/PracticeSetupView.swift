import SwiftData
import SwiftUI

struct PracticeSetupView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PracticeFlow.self) private var practiceFlow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \UserSceneRecord.createdAt, order: .reverse) private var userScenes: [UserSceneRecord]
    @State private var destinationID = "tokyo"
    @State private var languageCode = "ja"
    @State private var explanationLanguage = ExplanationLanguage.english
    @State private var difficulty = TrainingDifficulty.basic
    @State private var generationMode = GenerationMode.efficient
    @State private var questionCount = 5
    @State private var selectedSceneIDs: Set<String> = ["dining", "transit"]
    @State private var selectedKinds: Set<QuestionKind> = [.cloze, .multipleChoice, .spoken]
    @State private var showCustomScene = false
    @State private var showDestinationPicker = false
    @State private var didLoadSettings = false
    @State private var customDestination: Destination?

    private var destination: Destination {
        if let customDestination, customDestination.id == destinationID { return customDestination }
        return dependencies.catalog.destination(id: destinationID)
    }
    private var customScenes: [TravelScene] {
        userScenes
            .filter { $0.destinationID == destinationID && $0.isApproved }
            .map { TravelScene(id: $0.id.uuidString, title: $0.title, symbol: "square.and.pencil", context: $0.title, isLocal: true) }
    }
    private var allScenes: [TravelScene] {
        dependencies.catalog.commonScenes + customScenes
    }
    private var selectedScenes: [TravelScene] { allScenes.filter { selectedSceneIDs.contains($0.id) } }

    var body: some View {
        ZStack {
            PromptiBackground()
            PromptiScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    destinationSection
                    Divider()
                    sceneSection
                    Divider()
                    preferencesSection
                    if dependencies.settings.isPreGenerationEnabled {
                        InlineNotice(symbol: "clock.arrow.circlepath", text: "Advance preparation is on and can use additional provider tokens.", tone: .warning)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, PromptiSpacing.page)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Practice")
        .safeAreaInset(edge: .bottom) {
            startButtons
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PromptiSpacing.page)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(PromptiActionScrim())

        }
        .sheet(isPresented: $showCustomScene) {
            CustomSceneView(destination: destination)
        }
        .sheet(isPresented: $showDestinationPicker) {
            DestinationPickerView(selection: destinationSelection)
        }
        .onAppear { loadSettingsOnce() }
        .onChange(of: dependencies.settings.destinationID) { _, destinationID in
            synchronizeDestination(destinationID)
        }
        .onChange(of: dependencies.settings.languageCode) { _, languageCode in
            guard destination.languages.contains(where: { $0.code == languageCode }) else { return }
            self.languageCode = languageCode
        }
        .onChange(of: dependencies.settings.explanationLanguage) { _, explanationLanguage in
            self.explanationLanguage = explanationLanguage
        }
        .onChange(of: dependencies.settings.difficulty) { _, difficulty in
            self.difficulty = difficulty
        }
        .onChange(of: dependencies.settings.questionCount) { _, questionCount in
            self.questionCount = questionCount
        }
        .onChange(of: dependencies.settings.generationMode) { _, generationMode in
            self.generationMode = generationMode
        }
        .onChange(of: destinationID) { _, _ in
            if !destination.languages.contains(where: { $0.code == languageCode }) {
                languageCode = destination.languages[0].code
            }
            selectedSceneIDs = Set(dependencies.catalog.suggestedScenes.map(\.id))
        }
        .sensoryFeedback(.selection, trigger: difficulty)
        .sensoryFeedback(.selection, trigger: selectedSceneIDs)
    }

    private var destinationSection: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    destinationHeading
                    Spacer()
                    changeDestinationButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    destinationHeading
                    changeDestinationButton
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    destinationSymbol
                    languagePicker
                }
                VStack(alignment: .leading, spacing: 10) {
                    destinationSymbol
                    languagePicker
                }
            }
        }
        .padding(.vertical, 20)
    }

    private var destinationHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Travel brief")
                .font(PromptiTypography.section)
            Text("\(destination.localizedCity), \(destination.localizedCountry)")
                .font(.subheadline)
                .foregroundStyle(Color.promptMuted)
                .accessibilityIdentifier("practice.destination.\(destination.id)")
        }
    }

    private var changeDestinationButton: some View {
        Button("Change destination", systemImage: "map.fill") {
            showDestinationPicker = true
        }
        .buttonStyle(CompactGlassButtonStyle())
        .accessibilityIdentifier("practice.changeDestination")
    }

    private var destinationSymbol: some View {
        DestinationArtwork(destination: destination, size: 52)
    }

    private var languagePicker: some View {
        Picker("Language", selection: $languageCode) {
            ForEach(destination.languages) { language in
                Text(dynamicTypeSize.isAccessibilitySize ? language.localName : "\(language.localName) · \(language.localizedName)")
                    .tag(language.code)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.promptSurface, in: .rect(cornerRadius: PromptiRadius.control))
    }

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                SectionLabel("Scenes", subtitle: selectedSceneSummary)
                Button("Add a custom scene", systemImage: "plus") {
                    showCustomScene = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(GlassIconButtonStyle())
            }

            sceneGroup(
                "Everyday travel",
                symbol: "suitcase.rolling.fill",
                scenes: dependencies.catalog.commonScenes
            )

            if !customScenes.isEmpty {
                sceneGroup(
                    "Your scenes",
                    symbol: "square.and.pencil",
                    scenes: customScenes
                )
            }
        }
        .padding(.vertical, 20)
    }

    private func sceneGroup(
        _ title: String,
        symbol: String,
        scenes: [TravelScene]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.promptMuted)

            PromptiFlowLayout(spacing: 10) {
                ForEach(scenes) { scene in
                    let isSelected = selectedSceneIDs.contains(scene.id)
                    Button {
                        toggleScene(scene)
                    } label: {
                        SceneChoiceButton(
                            scene: scene,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("practice.scene.\(scene.id)")
                    .accessibilityLabel(Text(scene.localizedTitle))
                    .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
                }
            }
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Practice preferences", subtitle: "Shape each generated practice set.")

            PromptiSectionSurface {
                VStack(alignment: .leading, spacing: 12) {
                    preferenceHeading("Difficulty", subtitle: difficulty.detail, symbol: "gauge.with.dots.needle.67percent")
                    difficultyControl
                }
            }

            PromptiSectionSurface {
                VStack(alignment: .leading, spacing: 12) {
                    preferenceHeading("Question styles", subtitle: "Choose at least one exercise type.", symbol: "rectangle.on.rectangle")
                    questionTypeGrid
                }
            }

            PromptiSectionSurface {
                VStack(alignment: .leading, spacing: 14) {
                    preferenceHeading("Practice set", subtitle: "Set length and the language used for hints.", symbol: "rectangle.stack")

                    Stepper(value: $questionCount, in: 3...20) {
                        LabeledContent("Questions") {
                            Text("\(questionCount) questions")
                                .font(PromptiTypography.section)
                                .fontDesign(.rounded)
                        }
                    }

                    Divider()

                    LabeledContent("Explanations") {
                        Picker("Explanations", selection: $explanationLanguage) {
                            ForEach(ExplanationLanguage.allCases) { language in
                                Text(LocalizedStringKey(language.title)).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .accessibilityHint("Choose the language used for translations and explanations")
                }
            }

            PromptiSectionSurface {
                VStack(alignment: .leading, spacing: 12) {
                    preferenceHeading("Generation budget", subtitle: generationMode.detail, symbol: "speedometer")
                    Picker("Generation budget", selection: $generationMode) {
                        ForEach(GenerationMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.title)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("practice.generationMode")
                    Text(LocalizedStringKey(generationMode == .efficient
                        ? "Uses fewer provider tokens."
                        : "Requests extra candidates so review and duplicate filtering can still produce a full set."))
                        .font(.footnote)
                        .foregroundStyle(Color.promptMuted)
                }
            }
        }
        .padding(.vertical, 20)
    }

    private func preferenceHeading(_ title: String, subtitle: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.subheadline.weight(.semibold))
            Text(LocalizedStringKey(subtitle))
                .font(.footnote)
                .foregroundStyle(Color.promptMuted)
        }
    }

    private var difficultyControl: some View {
        Group {
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
                            .background(
                                item == difficulty ? Color.promptSelection : Color.promptSurface,
                                in: .rect(cornerRadius: PromptiRadius.control)
                            )
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
    }

    private var questionTypeGrid: some View {
        LazyVGrid(columns: questionTypeColumns, spacing: 10) {
            ForEach(QuestionKind.allCases) { kind in
                let isSelected = selectedKinds.contains(kind)
                Button {
                    toggleKind(kind)
                } label: {
                    Label(LocalizedStringKey(kind.title), systemImage: kind.symbol)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(isSelected ? Color.promptOnAction : Color.promptText)
                        .background(
                            isSelected ? Color.promptAction : Color.promptSurface,
                            in: .rect(cornerRadius: PromptiRadius.control)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
            }
        }
    }

    private var startButtons: some View {
        VStack(spacing: 10) {
            Button {
                practiceFlow.startGeneration(makeRequest(count: questionCount), configuration: dependencies.settings.provider)
            } label: {
                Label {
                    HStack(spacing: 5) {
                        Text("Generate questions")
                        Text("· \(questionCount)")
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityIdentifier("practice.generate")



        }
    }

    private var questionTypeColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.adaptive(minimum: 120), spacing: 10)]
        }
    }

    private var selectedSceneSummary: String {
        String(
            format: String(localized: "Selected scenes: %@"),
            "\(selectedSceneIDs.count)"
        )
    }

    private func toggleScene(_ scene: TravelScene) {
        if selectedSceneIDs.contains(scene.id) {
            if selectedSceneIDs.count > 1 { selectedSceneIDs.remove(scene.id) }
        } else {
            selectedSceneIDs.insert(scene.id)
        }
    }

    private func toggleKind(_ kind: QuestionKind) {
        if selectedKinds.contains(kind) {
            if selectedKinds.count > 1 { selectedKinds.remove(kind) }
        } else {
            selectedKinds.insert(kind)
        }
    }

    private func loadSettingsOnce() {
        guard !didLoadSettings else { return }
        didLoadSettings = true
        destinationID = dependencies.settings.destinationID
        languageCode = dependencies.settings.languageCode
        explanationLanguage = dependencies.settings.explanationLanguage
        difficulty = dependencies.settings.difficulty
        questionCount = dependencies.settings.questionCount
        generationMode = dependencies.settings.generationMode
        customDestination = dependencies.settings.customDestination
        selectedSceneIDs = Set(dependencies.catalog.suggestedScenes.map(\.id))
    }

    private func synchronizeDestination(_ destinationID: String) {
        guard destinationID != self.destinationID else { return }
        customDestination = dependencies.settings.customDestination
        self.destinationID = destinationID
    }

    private func makeRequest(count: Int) -> TrainingRequest {
        dependencies.settings.destinationID = destinationID
        dependencies.settings.languageCode = languageCode
        dependencies.settings.explanationLanguage = explanationLanguage
        dependencies.settings.difficulty = difficulty
        dependencies.settings.questionCount = questionCount
        dependencies.settings.generationMode = generationMode
        dependencies.settings.customDestination = customDestination
        let language = destination.languages.first(where: { $0.code == languageCode }) ?? destination.languages[0]
        return TrainingRequest(
            destination: destination,
            language: language,
            explanationLanguage: explanationLanguage,
            scenes: selectedScenes,
            customScene: nil,
            difficulty: difficulty,
            kinds: selectedKinds,
            count: count,
            generationMode: generationMode
        )
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

private struct CustomSceneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDependencies.self) private var dependencies
    let destination: Destination
    @State private var input = ""
    @State private var isReviewing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Short situation") {
                    TextField("e.g. buying a local pastry", text: $input)
                        .textInputAutocapitalization(.sentences)
                    Text("\(input.count) / 80")
                        .font(.caption)
                        .foregroundStyle(input.count > 80 ? Color.promptError : Color.promptMuted)
                }
                Section {
                    Text("Prompti asks your selected model to classify the scene before it is saved. Political persuasion, sexual content and prompt injection are rejected.")
                        .font(.footnote)
                        .foregroundStyle(Color.promptMuted)
                }
                if let errorMessage {
                    Section { InlineNotice(symbol: "exclamationmark.triangle", text: errorMessage, tone: .error) }
                }
            }
            .promptiScrollEdges()
            .scrollContentBackground(.hidden)
            .background(PromptiBackground())
            .navigationTitle("Custom scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isReviewing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await review() }
                    } label: {
                        if isReviewing { ProgressView() } else { Text("Add") }
                    }
                    .disabled(input.isEmpty || input.count > 80 || isReviewing)
                }
            }
        }
        .interactiveDismissDisabled(isReviewing)
    }

    private func review() async {
        isReviewing = true
        errorMessage = nil
        do {
            let result = try await dependencies.generation.reviewScene(input, configuration: dependencies.settings.provider)
            modelContext.insert(UserSceneRecord(destinationID: destination.id, title: result.normalized, isApproved: true))
            try modelContext.save()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
        isReviewing = false
    }
}
