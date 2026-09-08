import SwiftUI

struct DestinationPickerView: View {
    @Binding var selection: Destination
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var languageFilter = "all"
    @State private var showCustomDestination = false
    @State private var customCity = ""
    @State private var customCountry = ""
    @State private var pendingDestination: Destination?
    @State private var selectionFeedback = 0
    @State private var listPosition = ScrollPosition(edge: .top)

    private var availableDestinations: [Destination] {
        selection.isCustom ? [selection] + dependencies.catalog.destinations : dependencies.catalog.destinations
    }

    private var languages: [TrainingLanguage] {
        var seen = Set<String>()
        return dependencies.catalog.destinations
            .flatMap(\.languages)
            .filter { seen.insert($0.code).inserted }
            .sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredDestinations: [Destination] {
        availableDestinations.filter { destination in
            let matchesLanguage = languageFilter == "all" || destination.languages.contains { $0.code == languageFilter }
            let matchesSearch = query.isEmpty
                || destination.matchesSearch(query)
            return matchesLanguage && matchesSearch
        }
    }

    private var offersCustomDestination: Bool {
        !query.isEmpty && !availableDestinations.contains {
            [$0.city, $0.localizedCity, "\($0.city), \($0.country)", "\($0.localizedCity)，\($0.localizedCountry)"]
                .contains { $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PromptiBackground()
                VStack(spacing: 0) {
                    languageFilters
                    destinationList
                }
            }
            .navigationTitle("Choose a destination")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "City or country")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add a destination", systemImage: "plus") {
                        beginCustomDestination()
                    }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("destination.add")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("destination.close")
                }
            }
        }
        .accessibilityIdentifier("destination.picker")
        .sheet(isPresented: $showCustomDestination, onDismiss: selectPendingDestination) {
            CustomDestinationView(
                initialCity: customCity,
                initialCountry: customCountry,
                catalog: dependencies.catalog
            ) { destination in
                pendingDestination = destination
            }
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
    }

    @ViewBuilder
    private var destinationList: some View {
        if filteredDestinations.isEmpty && !offersCustomDestination {
            PromptiEmptyState(
                symbol: "map",
                title: "No match yet",
                message: "Search another city or add your own."
            )
            .frame(maxHeight: .infinity)
        } else {
            PromptiScrollView {
                LazyVStack(spacing: 12) {
                    if offersCustomDestination {
                        Button {
                            beginCustomDestination(from: query)
                        } label: {
                            AddDestinationRow(query: query)
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ForEach(filteredDestinations) { destination in
                        let isSelected = destination.id == selection.id
                        Button {
                            choose(destination)
                        } label: {
                            DestinationChoiceRow(
                                destination: destination,
                                isSelected: isSelected
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
                        .accessibilityIdentifier("destination.\(destination.id)")
                    }
                }
                .padding(.horizontal, PromptiSpacing.page)
                .padding(.top, 14)
                .padding(.bottom, 36)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($listPosition)
            .accessibilityIdentifier("destination.list")
            .onChange(of: languageFilter) { _, _ in listPosition.scrollTo(edge: .top) }
            .onChange(of: query) { _, _ in listPosition.scrollTo(edge: .top) }
        }
    }

    private var languageFilters: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button {
                        selectLanguageFilter("all")
                    } label: {
                        DestinationFilterChip(title: String(localized: "All"), isSelected: languageFilter == "all")
                    }
                    .id("all")
                    .accessibilityIdentifier("destination.filter.all")
                    .buttonStyle(.plain)
                    .accessibilityValue(Text(languageFilter == "all" ? "Selected" : "Not selected"))

                    ForEach(languages) { language in
                        Button {
                            selectLanguageFilter(language.code)
                        } label: {
                            DestinationFilterChip(title: language.localizedName, isSelected: languageFilter == language.code)
                        }
                        .id(language.code)
                        .accessibilityIdentifier("destination.filter.\(language.code)")
                        .buttonStyle(.plain)
                        .accessibilityValue(Text(languageFilter == language.code ? "Selected" : "Not selected"))
                    }
                }
                .padding(.horizontal, PromptiSpacing.page)
                .padding(.vertical, 10)
                .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: languageFilter)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("destination.filters")
            .onChange(of: languageFilter) { _, code in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.26)) {
                    proxy.scrollTo(code, anchor: .center)
                }
            }
        }
    }

    private func selectLanguageFilter(_ code: String) {
        languageFilter = code
        selectionFeedback += 1
    }

    private func choose(_ destination: Destination) {
        selection = destination
        selectionFeedback += 1
        dismiss()
    }

    private func beginCustomDestination(from query: String = "") {
        let parts = query.split(maxSplits: 1, whereSeparator: { $0 == "," || $0 == "，" })
        customCity = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        customCountry = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        showCustomDestination = true
    }

    private func selectPendingDestination() {
        guard let pendingDestination else { return }
        self.pendingDestination = nil
        choose(pendingDestination)
    }
}

private struct DestinationChoiceRow: View {
    let destination: Destination
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PromptiSpacing.related) {
            DestinationArtwork(destination: destination, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(destination.localizedCity)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .lineLimit(2)
                Text(destination.localizedCountry)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.promptMuted)
                    .lineLimit(2)
                PromptiFlowLayout(spacing: 6) {
                    ForEach(destination.languages) { language in
                        Text(verbatim: language.localizedName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.promptMuted)
                            .padding(.horizontal, PromptiSpacing.inline)
                            .padding(.vertical, 4)
                            .background(Color.promptSurfaceRaised, in: Capsule())
                    }
                }
                .padding(.top, PromptiSpacing.inline)
            }
            Spacer(minLength: 4)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.promptAction : Color.promptMuted)
                .padding(.top, 3)
        }
        .padding(16)
        .promptiSurface(tint: isSelected ? .promptSelection : .clear)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: PromptiRadius.surface, style: .continuous)
                    .strokeBorder(Color.promptAccent, lineWidth: 1.5)
            }
        }
    }
}

private struct AddDestinationRow: View {
    let query: String

    var body: some View {
        HStack(spacing: 14) {
            PromptiSymbolBadge(symbol: "plus", size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Add \(query)")
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .lineLimit(2)
                Text("Works with any destination")
                    .font(.subheadline)
                    .foregroundStyle(Color.promptMuted)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.promptAccent)
        }
        .padding(16)
        .promptiSurface()
    }
}

private struct DestinationFilterChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isSelected {
                Image(systemName: "checkmark")
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            Text(verbatim: title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isSelected ? Color.promptOnAction : Color.promptText)
        .padding(.horizontal, 15)
        .frame(minHeight: 44)
        .background(isSelected ? Color.promptAction : Color.promptSurface, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct CustomDestinationView: View {
    private enum Field: Hashable {
        case city
        case country
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var city: String
    @State private var country: String
    @FocusState private var focusedField: Field?
    let catalog: DestinationCatalog
    let onSave: (Destination) -> Void

    init(
        initialCity: String,
        initialCountry: String,
        catalog: DestinationCatalog,
        onSave: @escaping (Destination) -> Void
    ) {
        _city = State(initialValue: initialCity)
        _country = State(initialValue: initialCountry)
        self.catalog = catalog
        self.onSave = onSave
    }

    private var destination: Destination? {
        catalog.makeCustomDestination(city: city, country: country)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PromptiBackground()
                PromptiScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Color.promptAccent)
                            Text("Add destination")
                                .font(PromptiTypography.hero)
                                .fontDesign(.rounded)
                            Text("City and country are all we need.")
                                .font(.subheadline)
                                .foregroundStyle(Color.promptMuted)
                        }

                        VStack(spacing: 12) {
                            destinationField("City", text: $city, field: .city)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .country }
                            destinationField("Country or region", text: $country, field: .country)
                                .submitLabel(.done)
                                .onSubmit(save)
                        }

                        if let destination {
                            HStack(spacing: 10) {
                                Image(systemName: "character.bubble.fill")
                                    .foregroundStyle(Color.promptAccent)
                                Text("Default practice")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(destination.languages[0].localizedName)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color.promptAccent)
                            }
                            .padding(.horizontal, PromptiSpacing.page)
                            .frame(minHeight: 52)
                            .background(Color.promptSelection, in: RoundedRectangle(cornerRadius: PromptiRadius.compact))
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 88)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Use this destination", systemImage: "arrow.right", action: save)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(destination == nil)
                    .accessibilityIdentifier("destination.custom.save")
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(PromptiActionScrim())
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: dismiss.callAsFunction)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .accessibilityIdentifier("destination.custom")
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: destination != nil)
        .task {
            focusedField = city.isEmpty ? .city : .country
        }
    }

    private func destinationField(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(LocalizedStringKey(title), text: text)
            .font(.body.weight(.semibold))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(Color.promptSurfaceRaised, in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
    }

    private func save() {
        guard let destination else { return }
        onSave(destination)
        dismiss()
    }
}
