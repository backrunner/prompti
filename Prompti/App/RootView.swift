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
        .preferredColorScheme(nil)
    }
}

