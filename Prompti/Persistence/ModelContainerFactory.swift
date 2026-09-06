import SwiftData

enum PersistenceMode: Equatable, Sendable {
    case iCloud
    case localFallback
}

struct ModelContainerSetup {
    let container: ModelContainer
    let mode: PersistenceMode
}

enum PromptiSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [QuestionRecord.self, AttemptRecord.self, UserSceneRecord.self]
    }
}

enum PromptiMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PromptiSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum ModelContainerFactory {
    @MainActor
    static func make(inMemory: Bool = false) -> ModelContainer {
        makeSetup(inMemory: inMemory).container
    }

    @MainActor
    static func makeSetup(inMemory: Bool = false) -> ModelContainerSetup {
        let schema = Schema(versionedSchema: PromptiSchemaV1.self)
        do {
            let cloudConfiguration = ModelConfiguration(
                "PromptiCloud",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: inMemory ? .none : .automatic
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: PromptiMigrationPlan.self,
                configurations: [cloudConfiguration]
            )
            return ModelContainerSetup(container: container, mode: inMemory ? .localFallback : .iCloud)
        } catch {
            do {
                let localConfiguration = ModelConfiguration(
                    "PromptiLocal",
                    schema: schema,
                    isStoredInMemoryOnly: inMemory,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: PromptiMigrationPlan.self,
                    configurations: [localConfiguration]
                )
                return ModelContainerSetup(container: container, mode: .localFallback)
            } catch {
                fatalError("Unable to create Prompti data store: \(error.localizedDescription)")
            }
        }
    }
}
