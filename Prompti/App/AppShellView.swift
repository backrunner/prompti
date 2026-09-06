import SwiftUI

enum AppTab: Hashable {
    case today
    case practice
    case review
    case progress
}

struct AppShellView: View {
    @State private var selectedTab: AppTab
    @State private var practiceFlow = PracticeFlow()

    init() {
        #if DEBUG
        let initialTab: AppTab = ProcessInfo.processInfo.arguments.contains("-prompti-practice") ? .practice : .today
        #else
        let initialTab: AppTab = .today
        #endif
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        @Bindable var practiceFlow = practiceFlow

        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) {
                NavigationStack { HomeView(selectedTab: $selectedTab) }
            }
            Tab("Practice", systemImage: "text.book.closed.fill", value: .practice) {
                NavigationStack(path: $practiceFlow.path) {
                    PracticeSetupView()
                        .navigationDestination(for: PracticeRoute.self) { route in
                            practiceDestination(route)
                        }
                }
            }
            Tab("Review", systemImage: "arrow.counterclockwise.circle.fill", value: .review) {
                NavigationStack { ReviewView(selectedTab: $selectedTab) }
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: .progress) {
                NavigationStack { ProgressDashboardView(selectedTab: $selectedTab) }
            }
        }
        .environment(practiceFlow)
    }

    @ViewBuilder
    private func practiceDestination(_ route: PracticeRoute) -> some View {
        switch route {
        case .generation(let id):
            if let request = practiceFlow.request(for: id) {
                GenerationView(request: request) {
                    let origin = practiceFlow.cancel()
                    if origin == .quickQuestion {
                        selectedTab = .today
                    }
                }
            } else {
                MissingPracticeView {
                    _ = practiceFlow.cancel()
                }
            }
        case .session(let id):
            if let records = practiceFlow.records(for: id) {
                PracticeSessionView(records: records) {
                    let origin = practiceFlow.finish()
                    if origin == .quickQuestion {
                        selectedTab = .today
                    }
                }
            } else {
                MissingPracticeView {
                    _ = practiceFlow.cancel()
                }
            }
        }
    }
}

private struct MissingPracticeView: View {
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Practice unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("This practice set is no longer available.")
        } actions: {
            Button("Return to practice", action: action)
        }
    }
}
