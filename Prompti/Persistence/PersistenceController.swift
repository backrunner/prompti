import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData

/// Identity tokens are opaque: compare decoded tokens instead of assuming their archive bytes are stable.
@MainActor
final class AccountStoreRegistry {
    private struct Entry: Codable {
        var token: Data
        var scope: String
        var cloudOwner: String?
    }
    private var entries: [Entry]
    private var ownerScopes: [String: String]
    private var pendingImports: [String: [String]]
    private let defaults: UserDefaults
    private let key = "persistence.accountStores.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        ownerScopes = defaults.dictionary(forKey: key + ".owners") as? [String: String] ?? [:]
        pendingImports = defaults.dictionary(forKey: key + ".imports") as? [String: [String]] ?? [:]
    }

    func scope(for token: (any NSCoding & NSCopying & NSObjectProtocol)?) -> String {
        guard let token,
              let archive = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) else { return "guest" }
        if let entry = entries.first(where: { entry in
            guard let decoder = try? NSKeyedUnarchiver(forReadingFrom: entry.token) else { return false }
            decoder.requiresSecureCoding = false
            defer { decoder.finishDecoding() }
            guard let stored = decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject else { return false }
            return stored.isEqual(token)
        }) { return entry.scope }
        let scope = "account-" + UUID().uuidString
        entries.append(Entry(token: archive, scope: scope))
        save()
        return scope
    }

    func verifiedScope(_ scope: String, owner: String) -> String {
        guard let index = entries.firstIndex(where: { $0.scope == scope }) else { return scope }
        let existing = ownerScopes[owner] ?? entries.first(where: { $0.cloudOwner == owner })?.scope
        let resolved = existing ?? (entries[index].cloudOwner == nil ? scope : "account-" + UUID().uuidString)
        if resolved != scope, entries[index].cloudOwner == nil {
            pendingImports[resolved, default: []].append(scope)
        }
        entries[index].scope = resolved
        entries[index].cloudOwner = owner
        ownerScopes[owner] = resolved
        save()
        return resolved
    }

    func importScopes(for scope: String) -> [String] { pendingImports[scope] ?? [] }

    private func save() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
        defaults.set(ownerScopes, forKey: key + ".owners")
        defaults.set(pendingImports, forKey: key + ".imports")
    }
}

@MainActor
@Observable
final class PersistenceController {
    private(set) var container: ModelContainer
    private(set) var mode: PersistenceMode
    private(set) var epoch = UUID()
    private(set) var scope: String
    private(set) var isSwitching = false
    private(set) var status = "On this device"
    private(set) var lastSync: Date?
    private(set) var errorMessage: String?
    private(set) var importMessage: String?
    private(set) var importSources: [URL] = []
    private let registry: AccountStoreRegistry
    private let isInMemory: Bool
    private var refreshID = UUID()
    private var refreshing = false
    private var activeEvents = Set<UUID>()
    private var storeIdentifier: String?

    init(container: ModelContainer? = nil, mode: PersistenceMode? = nil, inMemory: Bool = false) {
        registry = AccountStoreRegistry()
        isInMemory = inMemory || container != nil
        let initialScope = (inMemory || container != nil) ? "test" : registry.scope(for: FileManager.default.ubiquityIdentityToken)
        scope = initialScope
        if let container {
            self.container = container
            self.mode = mode ?? .localFallback
        } else if isInMemory {
            self.container = ModelContainerFactory.make(inMemory: true)
            self.mode = .localFallback
        } else {
            do {
                let setup = try ModelContainerFactory.open(url: ModelContainerFactory.storeURL(scope: initialScope), cloud: false)
                self.container = setup.container
                self.mode = setup.mode
            } catch {
                self.container = ModelContainerFactory.make(inMemory: true)
                self.mode = .localFallback
                self.errorMessage = String(localized: "Learning data could not be opened. Retry before practicing.")
                self.status = "Learning data unavailable"
            }
        }
        findImportSources()
    }

    func refresh(accountChanged: Bool = false) async {
        guard !isInMemory, !refreshing || accountChanged else { return }
        let operationID = UUID()
        refreshID = operationID
        refreshing = true
        defer { if refreshID == operationID { refreshing = false; isSwitching = false } }
        let tokenScope = registry.scope(for: FileManager.default.ubiquityIdentityToken)
        if accountChanged || tokenScope != scope {
            isSwitching = true
            // Root replacement cancels tasks holding the previous ModelContext.
            guard replace(scope: tokenScope, cloud: false) else { return }
        }
        guard tokenScope != "guest" else {
            status = "On this device"
            return
        }
        do {
            let cloud = CKContainer(identifier: "iCloud.com.prompti.app")
            let accountStatus = try await cloud.accountStatus()
            guard refreshID == operationID else { return }
            guard accountStatus == .available else {
                if accountStatus == .noAccount { _ = replace(scope: "guest", cloud: false) }
                else if mode == .iCloud { _ = replace(scope: scope, cloud: false) }
                status = "iCloud account unavailable; saved on this device"
                return
            }
            let owner = try await cloud.userRecordID()
            guard refreshID == operationID,
                  registry.scope(for: FileManager.default.ubiquityIdentityToken) == tokenScope else { return }
            let verified = registry.verifiedScope(tokenScope, owner: ContentFingerprint.hash(owner.recordName))
            if verified != scope || mode != .iCloud {
                guard replace(scope: verified, cloud: true) else { return }
            }
            errorMessage = nil
            status = mode == .iCloud ? "iCloud ready; waiting for sync" : "iCloud unavailable; saved on this device"
        } catch {
            guard refreshID == operationID else { return }
            status = "Offline; saved on this device"
            // Keep the same account's local records available while CloudKit retries.
        }
    }

    @discardableResult
    private func replace(scope: String, cloud: Bool) -> Bool {
        do {
            let setup = try ModelContainerFactory.open(url: ModelContainerFactory.storeURL(scope: scope), cloud: cloud)
            self.scope = scope
            container = setup.container
            mode = setup.mode
            epoch = UUID()
            storeIdentifier = (try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType,
                at: ModelContainerFactory.storeURL(scope: scope), options: nil))?[NSStoreUUIDKey] as? String
            activeEvents.removeAll()
            lastSync = nil
            errorMessage = nil
            findImportSources()
            return true
        } catch {
            // Do not keep presenting the previous account's data after a failed switch.
            container = ModelContainerFactory.make(inMemory: true)
            mode = .localFallback
            epoch = UUID()
            self.scope = scope
            errorMessage = String(localized: "Learning data could not be opened. Retry before practicing.")
            status = "Learning data unavailable"
            return false
        }
    }

    func handleCloudEvent(_ notification: Notification) {
        guard mode == .iCloud,
              let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
              event.storeIdentifier == storeIdentifier else { return }
        if event.endDate == nil {
            activeEvents.insert(event.identifier)
            status = "Syncing with iCloud"
        } else {
            activeEvents.remove(event.identifier)
            if event.succeeded {
                if event.type != .setup { lastSync = event.endDate }
                status = activeEvents.isEmpty ? "iCloud sync finished" : "Syncing with iCloud"
            } else {
                status = Self.syncFailureStatus(event.error)
            }
        }
    }

    static func syncFailureStatus(_ error: Error?) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .quotaExceeded: return "iCloud storage is full; saved on this device"
            case .notAuthenticated: return "iCloud account unavailable; saved on this device"
            case .networkUnavailable, .networkFailure: return "Offline; saved on this device"
            default: break
            }
        }
        if let nested = (error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? Error {
            if let cloudError = nested as? CKError { return syncFailureStatus(cloudError) }
        }
        return "Sync paused; saved on this device"
    }

    func noteSave() {
        if mode == .iCloud { status = "Saved on this device; waiting for iCloud" }
    }

    func findImportSources() {
        guard !isInMemory else { return }
        let legacy = ["PromptiCloud", "PromptiLocal"].map { ModelConfiguration($0, cloudKitDatabase: .none).url }
        let guest = scope == "guest" ? [] : [ModelContainerFactory.storeURL(scope: "guest")]
        let pending = registry.importScopes(for: scope).map { ModelContainerFactory.storeURL(scope: $0) }
        importSources = (legacy + guest + pending).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func importLocalData() {
        guard !isSwitching, errorMessage == nil else { return }
        do {
            var count = 0
            for url in importSources {
                let source = try ModelContainerFactory.open(url: url, cloud: false).container
                count += try LearningDataImport.merge(from: source.mainContext, into: container.mainContext)
            }
            importMessage = String(localized: "Imported \(count) records. Existing history was preserved.")
            noteSave()
        } catch { importMessage = error.localizedDescription }
    }
}
