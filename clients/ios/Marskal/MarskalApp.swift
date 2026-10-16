import AppIntents
import BackgroundTasks
import MarskalKit
import SwiftUI

@main
struct MarskalApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, model.locale)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.activate()
            case .background:
                Task {
                    await model.deactivate()
                    await scheduleRefresh()
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTask)) {
            await scheduleRefresh()
            await model.backgroundSync()
        }
    }

    // The system decides when, if at all; this asks for no sooner than 15
    // minutes from now.
    private func scheduleRefresh() async {
        let request = BGAppRefreshTaskRequest(identifier: AppModel.refreshTask)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? await BGTaskScheduler.shared.submitTaskRequest(request)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.session == nil {
                SignInView()
            } else {
                TasksView()
            }
        }
        .alert(item: $model.problem) { problem in
            Alert(title: Text(problem.title), message: Text(problem.message))
        }
    }
}
