import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Prompti

@MainActor
@Suite("Storage upgrades and account isolation")
struct CapabilityPersistenceTests {
    private func request() -> TrainingRequest {
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: "tokyo")
        return TrainingRequest(destination: destination, language: destination.languages[0], explanationLanguage: .simplifiedChinese,
                               scenes: [catalog.commonScenes[0]], difficulty: .basic, kinds: [.multipleChoice], count: 1)
    }

    private func question() -> GeneratedQuestion {
        GeneratedQuestion(kind: .multipleChoice, prompt: "お会計をお願いします。", options: ["はい", "いいえ", "駅", "朝"].map { QuestionOption(text: $0) }, correctAnswer: "はい", translation: "请结账。", explanation: "礼貌的餐厅用语。")
    }

    @Test("Real version 1 disk store migrates without losing question or event IDs")
    func diskMigration() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "learning.store")
        let request = request()
        let original = question()
        let attemptID: UUID = try autoreleasepool {
            let schema = Schema(versionedSchema: PromptiSchemaV1.self)
            let config = ModelConfiguration("legacy", schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            let record = PromptiSchemaV1.QuestionRecord(question: original, request: request, scene: request.scenes[0])
            let attempt = PromptiSchemaV1.AttemptRecord(question: record, result: .incorrect, submittedAnswer: "駅")
            record.isQuarantined = true
            old.mainContext.insert(record)
            old.mainContext.insert(attempt)
            old.mainContext.insert(PromptiSchemaV1.UserSceneRecord(destinationID: "tokyo", title: "Lunch", isApproved: true))
            try old.mainContext.save()
            return attempt.id
        }
        let upgraded = try ModelContainerFactory.open(url: url, cloud: false).container
        let record = try #require(upgraded.mainContext.fetch(FetchDescriptor<QuestionRecord>()).first)
        let attempt = try #require(upgraded.mainContext.fetch(FetchDescriptor<AttemptRecord>()).first)
        #expect(record.id == original.id)
        #expect(record.prompt == original.prompt)
        #expect(record.isQuarantined)
        #expect(record.explanationLanguageCode.isEmpty) // Unknown legacy locale stays unknown.
        #expect(record.clozeData == nil)
        #expect(attempt.id == attemptID)
        #expect(attempt.questionID == original.id)
        #expect(attempt.result == .incorrect)
        #expect(!attempt.localDayKey.isEmpty)
        #expect(try upgraded.mainContext.fetchCount(FetchDescriptor<UserSceneRecord>()) == 1)
        let fresh = QuestionRecord(question: question(), request: request, scene: request.scenes[0])
        upgraded.mainContext.insert(fresh)
        try upgraded.mainContext.save()
        #expect(fresh.explanationLanguageCode == "zh-Hans")
    }

    @Test("Local reopen keeps the same account's records while other accounts and guests stay separate")
    func accountFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = ModelContainerFactory.storeURL(scope: "account-A", root: root)
        try autoreleasepool {
            let container = try ModelContainerFactory.open(url: url, cloud: false).container
            let request = request()
            container.mainContext.insert(QuestionRecord(question: question(), request: request, scene: request.scenes[0]))
            try container.mainContext.save()
        }
        let reopened = try ModelContainerFactory.open(url: url, cloud: false).container
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<QuestionRecord>()) == 1)
        for scope in ["account-B", "guest"] {
            let other = try ModelContainerFactory.open(url: ModelContainerFactory.storeURL(scope: scope, root: root), cloud: false).container
            #expect(try other.mainContext.fetchCount(FetchDescriptor<QuestionRecord>()) == 0)
        }
    }

    @Test("Opaque identity tokens survive restart and account return, without sharing owner stores")
    func identities() throws {
        let suite = "prompti-registry-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = AccountStoreRegistry(defaults: defaults)
        let a = registry.scope(for: "token-A" as NSString)
        let b = registry.scope(for: "token-B" as NSString)
        #expect(a != b)
        #expect(registry.scope(for: nil) == "guest")
        #expect(registry.verifiedScope(a, owner: "owner-A") == a)
        #expect(registry.verifiedScope(b, owner: "owner-B") == b)
        let restarted = AccountStoreRegistry(defaults: defaults)
        #expect(restarted.scope(for: "token-A" as NSString) == a)
        let newToken = restarted.scope(for: "new-token-A" as NSString)
        #expect(restarted.verifiedScope(newToken, owner: "owner-A") == a)
        #expect(restarted.importScopes(for: a) == [newToken])
        let changed = restarted.verifiedScope(a, owner: "owner-C")
        #expect(changed != a && changed != b)
        #expect(restarted.verifiedScope(changed, owner: "owner-A") == a)
    }

    @Test("Sync failures distinguish full storage, account sign-out and offline status")
    func cloudStatus() {
        #expect(PersistenceController.syncFailureStatus(CKError(.quotaExceeded)) == "iCloud storage is full; saved on this device")
        #expect(PersistenceController.syncFailureStatus(CKError(.notAuthenticated)) == "iCloud account unavailable; saved on this device")
        #expect(PersistenceController.syncFailureStatus(CKError(.networkFailure)) == "Offline; saved on this device")
    }

    @Test("Synced UUID copies do not duplicate scores or lose quarantine")
    func syncedCopies() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let request = request()
        let original = question()
        let first = QuestionRecord(question: original, request: request, scene: request.scenes[0])
        let second = QuestionRecord(question: original, request: request, scene: request.scenes[0])
        second.isQuarantined = true
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        let event = AttemptRecord(question: first, result: .correct, submittedAnswer: "はい")
        let copy = AttemptRecord(question: second, result: .correct, submittedAnswer: "はい")
        copy.id = event.id
        container.mainContext.insert(event)
        container.mainContext.insert(copy)
        try container.mainContext.save()
        #expect(QuestionRecord.canonical(in: [first, second]).count == 1)
        #expect(QuestionRecord.canonical(in: [first, second])[0].isQuarantined)
        #expect(AttemptRecord.scored(in: [event, copy]).count == 1)
    }

    @Test("Repeated local imports preserve histories and quarantine without duplicates")
    func idempotentImport() throws {
        let source = ModelContainerFactory.make(inMemory: true)
        let target = ModelContainerFactory.make(inMemory: true)
        let request = request()
        let record = QuestionRecord(question: question(), request: request, scene: request.scenes[0])
        source.mainContext.insert(record)
        let attempt = AttemptRecord(question: record, result: .incorrect, submittedAnswer: "駅")
        attempt.sessionID = UUID()
        source.mainContext.insert(attempt)
        try source.mainContext.save()
        #expect(try LearningDataImport.merge(from: source.mainContext, into: target.mainContext) == 2)
        record.isQuarantined = true
        source.mainContext.insert(AttemptRecord(question: record, result: .reported, submittedAnswer: ""))
        try source.mainContext.save()
        #expect(try LearningDataImport.merge(from: source.mainContext, into: target.mainContext) == 1)
        #expect(try LearningDataImport.merge(from: source.mainContext, into: target.mainContext) == 0)
        let imported = try #require(target.mainContext.fetch(FetchDescriptor<QuestionRecord>()).first)
        let events = try target.mainContext.fetch(FetchDescriptor<AttemptRecord>())
        #expect(imported.isQuarantined)
        #expect(events.count == 2)
        #expect(events.first(where: { $0.id == attempt.id })?.questionSnapshot == attempt.questionSnapshot)
        #expect(events.first(where: { $0.id == attempt.id })?.sessionID == attempt.sessionID)
        #expect(AttemptRecord.scored(in: events).isEmpty)
    }
}
