import Foundation
import SwiftData

enum PersistenceMode: Equatable, Sendable {
    case iCloud
    case localFallback
}

struct ModelContainerSetup {
    let container: ModelContainer
    let mode: PersistenceMode
}

enum PromptiMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PromptiSchemaV1.self, PromptiSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: PromptiSchemaV1.self, toVersion: PromptiSchemaV2.self)]
    }
}

enum ModelContainerFactory {
    // CloudKit clients share the configured container; keep signing entitlements in sync.
    static let cloudContainerIdentifier = Bundle.main.object(forInfoDictionaryKey: "PromptiCloudContainerIdentifier") as? String
        ?? "iCloud.com.alkinum.prompti"

    static func storeURL(scope: String, root: URL = URL.applicationSupportDirectory) -> URL {
        root.appending(path: "PromptiAccounts", directoryHint: .isDirectory)
            .appending(path: ContentFingerprint.hash(scope) + ".store")
    }

    @MainActor
    static func open(url: URL, cloud: Bool) throws -> ModelContainerSetup {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: PromptiSchemaV2.self)
        func container(cloudEnabled: Bool) throws -> ModelContainer {
            let configuration = ModelConfiguration("Prompti", schema: schema, url: url,
                cloudKitDatabase: cloudEnabled ? .private(cloudContainerIdentifier) : .none)
            return try ModelContainer(for: schema, migrationPlan: PromptiMigrationPlan.self, configurations: [configuration])
        }
        if cloud, let container = try? container(cloudEnabled: true) {
            return ModelContainerSetup(container: container, mode: .iCloud)
        }
        // Cloud failure must never select a different file for the same owner.
        return ModelContainerSetup(container: try container(cloudEnabled: false), mode: .localFallback)
    }

    @MainActor
    static func make(inMemory: Bool = false) -> ModelContainer { makeSetup(inMemory: inMemory).container }

    @MainActor
    static func makeSetup(inMemory: Bool = false) -> ModelContainerSetup {
        do {
            if !inMemory { return try open(url: storeURL(scope: "guest"), cloud: false) }
            let schema = Schema(versionedSchema: PromptiSchemaV2.self)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return ModelContainerSetup(container: try ModelContainer(for: schema, migrationPlan: PromptiMigrationPlan.self,
                                                                    configurations: [configuration]), mode: .localFallback)
        } catch {
            fatalError("Unable to create Prompti data store: \(error.localizedDescription)")
        }
    }
}
