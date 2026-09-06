import SwiftData
import SwiftUI

@main
struct PromptiApp: App {
    @State private var dependencies: AppDependencies

    init() {
        _dependencies = State(initialValue: AppDependencies())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .modelContainer(dependencies.modelContainer)
                .tint(.promptAccent)
        }
    }
}
