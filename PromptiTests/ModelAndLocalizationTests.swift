import Foundation
import Testing
@testable import Prompti

@Suite("Model selection and localization")
struct ModelAndLocalizationTests {
    @Test("Request ranking puts unknown usage last and preserves deterministic ties")
    func ranking() {
        let snapshot = OpenRouterRecommendations(source: "fixture", asOf: "2026-09-06", models: [
            .init(id: "unknown", name: "A"), .init(id: "zero", name: "B", weeklyRequests: 0),
            .init(id: "low", name: "C", weeklyRequests: 10), .init(id: "high", name: "D", weeklyRequests: 30),
            .init(id: "tie", name: "A", weeklyRequests: 10)
        ])
        #expect(snapshot.sortedModels.map(\.id) == ["high", "tie", "low", "zero", "unknown"])
    }

    @Test("The shipped catalog has source metadata and the default is the first ranked model")
    func bundledCatalog() throws {
        let catalog = ModelRecommendations.openRouter
        #expect(catalog.source == "https://openrouter.ai/rankings")
        #expect(!catalog.asOf.isEmpty)
        #expect(catalog.models.count >= 6)
        #expect(Set(catalog.models.map(\.id)).count == catalog.models.count)
        #expect(try #require(catalog.models.first).weeklyRequests != nil)
        #expect(ProviderKind.openRouterOAuth.defaultModel == catalog.models.first?.id)
    }

    @Test("New shortcuts use existing adapters, with exact compatible endpoint routing", arguments: [
        (ProviderPreset.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
        (.deepSeek, "https://api.deepseek.com/v1/chat/completions"),
        (.openAI, "https://api.openai.com/v1/responses"),
        (.anthropic, "https://api.anthropic.com/v1/messages")
    ])
    func presetEndpoints(_ preset: ProviderPreset, _ endpoint: String) throws {
        let configuration = preset.configuration
        #expect(ProviderPreset.matching(configuration) == preset)
        #expect(configuration.structuredOutputSupport == .unknown)
        #expect(try RemoteAIClient(configuration: configuration, apiKey: "fixture").endpointURL().absoluteString == endpoint)
    }

    @Test("Custom gateways keep their model and do not get unrelated vendor suggestions")
    func customModelPreserved() throws {
        let saved = Data(#"{"kind":"openAIChat","baseURL":"https://gateway.example.com/v1","model":"my-existing-model","structuredOutputSupport":"supported"}"#.utf8)
        let configuration = try JSONDecoder().decode(ProviderConfiguration.self, from: saved)
        #expect(ProviderPreset.matching(configuration) == .compatible)
        #expect(ProviderPreset.models(for: configuration).isEmpty)
        #expect(configuration.model == "my-existing-model")
        #expect(configuration.structuredOutputSupport == .supported)
        var responses = configuration
        responses.kind = .openAIResponses
        #expect(ProviderPreset.models(for: responses).isEmpty)
    }

    @Test("Catalog translations are display-only; user text is never translated as a key")
    func localizedCatalog() throws {
        let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try #require(Bundle(path: path))
        #expect(CatalogLocalization.destinationName(id: "tokyo", fallback: "Tokyo", bundle: chinese) == "东京")
        #expect(CatalogLocalization.destinationName(id: "custom-japan-tokyo", fallback: "Tokyo", bundle: chinese) == "Tokyo")
        #expect(CatalogLocalization.sceneTitle(id: "dining", fallback: "Dining", bundle: chinese) == "用餐")
        #expect(CatalogLocalization.sceneTitle(id: UUID().uuidString, fallback: "Dining", bundle: chinese) == "Dining")
        #expect(CatalogLocalization.sceneTitle(id: "custom-japan-nikko-explore", fallback: "Around Nikko", bundle: chinese) == "Nikko周边")
        #expect(DestinationCatalog().destination(id: "tokyo").city == "Tokyo")
        for destination in DestinationCatalog().destinations {
            #expect(CatalogLocalization.text(destination.city, bundle: chinese) != destination.city)
            #expect(CatalogLocalization.text(destination.country, bundle: chinese) != destination.country)
            #expect(CatalogLocalization.text(destination.landmarkName, bundle: chinese) != destination.landmarkName)
        }
    }

    @Test("New explanation preferences follow the interface language")
    func explanationDefault() {
        #expect(ExplanationLanguage.suggested(preferredLanguages: ["zh-Hans-SG", "en"]) == .simplifiedChinese)
        #expect(ExplanationLanguage.suggested(preferredLanguages: ["en-US", "zh-Hans"]) == .english)
    }

    @Test("English question counts use singular and plural")
    func plurals() throws {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: path))
        let locale = Locale(identifier: "en_US")
        let one = 1
        let two = 2
        #expect(String(localized: "\(one) questions", bundle: english, locale: locale) == "1 question")
        #expect(String(localized: "\(two) questions", bundle: english, locale: locale) == "2 questions")
    }
}
