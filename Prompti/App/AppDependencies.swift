import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppDependencies {
    let persistence: PersistenceController
    var modelContainer: ModelContainer { persistence.container }
    var persistenceMode: PersistenceMode { persistence.mode }
    let settings: AppSettings
    let secureStore: SecureStore
    let catalog: DestinationCatalog
    let generation: QuestionGenerationService
    let usage: UsageLedger
    let inventoryConditions = InventoryConditions()

    init(
        modelContainer: ModelContainer? = nil,
        persistenceMode: PersistenceMode? = nil,
        settings: AppSettings? = nil,
        secureStore: SecureStore? = nil,
        catalog: DestinationCatalog = DestinationCatalog()
    ) {
        persistence = PersistenceController(container: modelContainer, mode: persistenceMode, inMemory: Self.usesCleanUITestData)
        self.settings = settings ?? Self.makeSettings()
        let secureStore = secureStore ?? Self.makeSecureStore()
        self.secureStore = secureStore
        secureStore.migrateLegacyKey(for: self.settings.provider)
        self.catalog = catalog
        let usage = UsageLedger()
        self.usage = usage
        let activeSettings = self.settings
        generation = QuestionGenerationService(secureStore: secureStore, usageSink: { entry in await usage.record(entry) },
            reviewMode: { await activeSettings.questionReviewMode })
    }

    private static var usesCleanUITestData: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-prompti-ui-clean-data")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        false
        #endif
    }

    private static func makeSecureStore() -> SecureStore {
        #if DEBUG
        if usesCleanUITestData {
            return SecureStore(service: "com.prompti.app.ui-tests." + UUID().uuidString)
        }
        #endif
        return SecureStore()
    }

    private static func makeSettings() -> AppSettings {
        #if DEBUG
        if usesCleanUITestData {
            let suiteName = "com.prompti.app.ui-tests"
            guard let defaults = UserDefaults(suiteName: suiteName) else { return AppSettings() }
            defaults.removePersistentDomain(forName: suiteName)
            return AppSettings(defaults: defaults)
        }
        #endif
        return AppSettings()
    }
}
