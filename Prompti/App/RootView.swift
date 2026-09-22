import SwiftUI

struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            if dependencies.settings.hasCompletedOnboarding {
                AppShellView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(uiTestColorScheme)
    }

    private var uiTestColorScheme: ColorScheme? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-prompti-ui-clean-data") {
            if arguments.contains("-prompti-ui-dark") { return .dark }
            if arguments.contains("-prompti-ui-light") { return .light }
        }
        #endif
        return nil
    }
}
