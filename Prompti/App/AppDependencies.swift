import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppDependencies {
    let modelContainer: ModelContainer
    let persistenceMode: PersistenceMode
    let settings: AppSettings
    let secureStore: SecureStore
    let catalog: DestinationCatalog
    let generation: QuestionGenerationService

    init(
        modelContainer: ModelContainer? = nil,
        persistenceMode: PersistenceMode? = nil,
        settings: AppSettings? = nil,
        secureStore: SecureStore = SecureStore(),
        catalog: DestinationCatalog = DestinationCatalog()
    ) {
        if let modelContainer {
            self.modelContainer = modelContainer
            self.persistenceMode = persistenceMode ?? .localFallback
        } else {
            let setup = ModelContainerFactory.makeSetup(inMemory: Self.usesCleanUITestData)
            self.modelContainer = setup.container
            self.persistenceMode = setup.mode
        }
        self.settings = settings ?? Self.makeSettings()
        self.secureStore = secureStore
        secureStore.migrateLegacyKey(for: self.settings.provider)
        self.catalog = catalog
        generation = QuestionGenerationService(secureStore: secureStore)
    }

    private static var usesCleanUITestData: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-prompti-ui-clean-data")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        false
        #endif
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
