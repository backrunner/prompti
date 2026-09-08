import Foundation

/// Presentation only: IDs, stored snapshots, custom text and provider prompts
/// retain their original values when the interface language changes.
enum CatalogLocalization {
    static let catalog = DestinationCatalog()
    static let destinations = Dictionary(uniqueKeysWithValues: catalog.destinations.map { ($0.id, $0) })
    static let scenes = Dictionary(uniqueKeysWithValues:
        (catalog.commonScenes + catalog.destinations.flatMap(\.localScenes)).map { ($0.id, $0) })

    static func text(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func destinationName(id: String, fallback: String, bundle: Bundle = .main) -> String {
        guard let destination = destinations[id] else { return fallback }
        return text(destination.city, bundle: bundle)
    }

    static func sceneTitle(id: String, fallback: String, bundle: Bundle = .main) -> String {
        if let scene = scenes[id] { return text(scene.title, bundle: bundle) }
        if id.hasPrefix("custom-"), id.hasSuffix("-explore"), fallback.hasPrefix("Around ") {
            return String(format: text("Around %@", bundle: bundle), String(fallback.dropFirst(7)))
        }
        return fallback
    }
}

extension Destination {
    var localizedCity: String { isCustom ? city : CatalogLocalization.text(city) }
    var localizedCountry: String { isCustom ? country : CatalogLocalization.text(country) }
    var localizedLandmark: String { isCustom ? landmarkName : CatalogLocalization.text(landmarkName) }

    func matchesSearch(_ query: String) -> Bool {
        [city, country, localizedCity, localizedCountry, landmarkName, localizedLandmark,
         "\(city), \(country)", "\(localizedCity)，\(localizedCountry)"]
            .contains { $0.localizedStandardContains(query) }
    }
}

extension TrainingLanguage {
    var localizedName: String { CatalogLocalization.text(name) }
}

extension TravelScene {
    var localizedTitle: String { CatalogLocalization.sceneTitle(id: id, fallback: title) }
}

extension QuestionRecord {
    var localizedDestinationName: String {
        CatalogLocalization.destinationName(id: destinationID, fallback: destinationName)
    }
    var localizedSceneTitle: String { CatalogLocalization.sceneTitle(id: sceneID, fallback: sceneTitle) }
}

extension AttemptRecord {
    var localizedSceneTitle: String {
        let snapshot = questionSnapshot.flatMap { try? JSONDecoder().decode(GeneratedQuestion.self, from: $0) }
        return CatalogLocalization.sceneTitle(id: snapshot?.sceneID ?? "", fallback: sceneTitle)
    }
}

