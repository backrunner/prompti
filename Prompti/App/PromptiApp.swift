import CoreData
import CloudKit
import SwiftData
import SwiftUI

@main
struct PromptiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dependencies: AppDependencies

    init() {
        _dependencies = State(initialValue: AppDependencies())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let message = dependencies.persistence.errorMessage {
                    PromptiRecoveryView(symbol: "externaldrive.badge.exclamationmark", title: "Learning data unavailable",
                                        message: message, actionTitle: "Try again") {
                        Task { await dependencies.persistence.refresh(accountChanged: true) }
                    }
                } else {
                    RootView().id(dependencies.persistence.epoch)
                        .disabled(dependencies.persistence.isSwitching)
                }
            }
                .environment(dependencies)
                .modelContainer(dependencies.modelContainer)
                .tint(.promptAccent)
                .foregroundStyle(Color.promptText)
                .task { await dependencies.persistence.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await dependencies.persistence.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
                    Task { await dependencies.persistence.refresh(accountChanged: true) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    Task { await dependencies.persistence.refresh(accountChanged: true) }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)) {
                    dependencies.persistence.handleCloudEvent($0)
                }
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    dependencies.persistence.noteSave()
                }
        }
    }
}
