import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let onboarding = "onboarding.completed"
        static let destination = "training.destination"
        static let language = "training.language"
        static let explanationLanguage = "training.explanationLanguage"
        static let difficulty = "training.difficulty"
        static let questionCount = "training.questionCount"
        static let provider = "provider.configuration"
        static let preGeneration = "generation.prefetch"
        static let customDestination = "training.customDestination"
        static let inventoryTarget = "generation.inventoryTarget"
        static let dailyPreparationLimit = "generation.dailyLimit"
        static let preparationWiFiOnly = "generation.wifiOnly"
        static let preparationBudgetDay = "generation.budgetDay"
        static let preparationBudgetUsed = "generation.budgetUsed"
    }

    private let defaults: UserDefaults

    var speechRate: Float { didSet { defaults.set(speechRate, forKey: "speech.rate") } }

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) } }
    var destinationID: String { didSet { defaults.set(destinationID, forKey: Key.destination) } }
    var languageCode: String { didSet { defaults.set(languageCode, forKey: Key.language) } }
    var explanationLanguage: ExplanationLanguage { didSet { defaults.set(explanationLanguage.rawValue, forKey: Key.explanationLanguage) } }
    var difficulty: TrainingDifficulty { didSet { defaults.set(difficulty.rawValue, forKey: Key.difficulty) } }
    var questionCount: Int { didSet { defaults.set(questionCount, forKey: Key.questionCount) } }
    var provider: ProviderConfiguration { didSet { saveProvider() } }
    var isPreGenerationEnabled: Bool { didSet { defaults.set(isPreGenerationEnabled, forKey: Key.preGeneration) } }
    var customDestination: Destination? { didSet { saveCustomDestination() } }
    var inventoryTarget: Int { didSet { defaults.set(inventoryTarget, forKey: Key.inventoryTarget) } }
    var dailyPreparationLimit: Int { didSet { defaults.set(dailyPreparationLimit, forKey: Key.dailyPreparationLimit) } }
    var preparationWiFiOnly: Bool { didSet { defaults.set(preparationWiFiOnly, forKey: Key.preparationWiFiOnly) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        speechRate = min(0.55, max(0.3, defaults.object(forKey: "speech.rate") as? Float ?? 0.44))
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        destinationID = defaults.string(forKey: Key.destination) ?? "tokyo"
        languageCode = defaults.string(forKey: Key.language) ?? "ja"
        explanationLanguage = ExplanationLanguage(rawValue: defaults.string(forKey: Key.explanationLanguage) ?? "") ?? .english
        difficulty = TrainingDifficulty(rawValue: defaults.string(forKey: Key.difficulty) ?? "") ?? .basic
        let storedCount = defaults.integer(forKey: Key.questionCount)
        questionCount = storedCount == 0 ? 5 : min(20, max(3, storedCount))
        inventoryTarget = min(20, max(3, defaults.object(forKey: Key.inventoryTarget) as? Int ?? 3))
        dailyPreparationLimit = min(50, max(3, defaults.object(forKey: Key.dailyPreparationLimit) as? Int ?? 12))
        preparationWiFiOnly = defaults.object(forKey: Key.preparationWiFiOnly) as? Bool ?? true
        isPreGenerationEnabled = defaults.bool(forKey: Key.preGeneration)
        if let data = defaults.data(forKey: Key.customDestination) {
            customDestination = try? JSONDecoder().decode(Destination.self, from: data)
        } else {
            customDestination = nil
        }
        if let data = defaults.data(forKey: Key.provider),
           let decoded = try? JSONDecoder().decode(ProviderConfiguration.self, from: data) {
            provider = decoded
        } else {
            provider = ProviderConfiguration()
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-demo") {
            hasCompletedOnboarding = true
            destinationID = "tokyo"
            languageCode = "ja"
            explanationLanguage = .english
            provider = ProviderConfiguration(kind: .openAIResponses, baseURL: "https://api.openai.com", model: "demo")
        }
        if ProcessInfo.processInfo.arguments.contains("-prompti-onboarding") {
            hasCompletedOnboarding = false
        }
        #endif
    }

    private func saveProvider() {
        guard let data = try? JSONEncoder().encode(provider) else { return }
        defaults.set(data, forKey: Key.provider)
    }

    private func saveCustomDestination() {
        guard let customDestination else {
            defaults.removeObject(forKey: Key.customDestination)
            return
        }
        defaults.set(try? JSONEncoder().encode(customDestination), forKey: Key.customDestination)
    }

    func selectedDestination(in catalog: DestinationCatalog) -> Destination {
        if let customDestination, customDestination.id == destinationID {
            return customDestination
        }
        return catalog.destination(id: destinationID)
    }

    func selectDestination(_ destination: Destination, in catalog: DestinationCatalog) {
        destinationID = destination.id
        customDestination = catalog.contains(id: destination.id) ? nil : destination
        if !destination.languages.contains(where: { $0.code == languageCode }) {
            languageCode = destination.languages[0].code
        }
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }

    /// Reserve before calling a provider. Failed or cancelled calls may still
    /// incur charges, so their requested questions continue to use the budget.
    func reservePreparationCount(_ requested: Int, now: Date = .now) -> Int {
        let day = PracticeMetrics.localDayKey(for: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let previousDay = defaults.string(forKey: Key.preparationBudgetDay) ?? ""
        if day > previousDay {
            defaults.set(day, forKey: Key.preparationBudgetDay)
            defaults.set(0, forKey: Key.preparationBudgetUsed)
        }
        let used = defaults.integer(forKey: Key.preparationBudgetUsed)
        let allowed = max(0, min(requested, dailyPreparationLimit - used))
        defaults.set(used + allowed, forKey: Key.preparationBudgetUsed)
        return allowed
    }
}
