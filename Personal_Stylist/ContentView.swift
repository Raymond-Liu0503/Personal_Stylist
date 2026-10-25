import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if model.starting {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(StylistTheme.background)
                    .accessibilityLabel("Opening Personal Stylist")
            } else if model.startupFailed {
                Page(title: "Unable to start") {
                    NoticeView(error: model.error)
                    StylistButton(title: "Retry") { Task { await model.start() } }
                    StylistButton(title: "Reset sign-in", secondary: true) { Task { await model.resetStartup() } }.disabled(model.busy)
                }
            } else if !model.signedIn || (model.bootstrap != nil && !model.onboarded) {
                NavigationStack {
                    OnboardingView(model: model)
                        .toolbar { if model.signedIn { Button("Account") { model.sheet = .account } } }
                }
            } else {
                NavigationStack {
                    Group {
                        switch model.flow {
                        case .home, .camera: CameraView(model: model, camera: camera)
                        case .review: ReviewView(model: model)
                        case .processing: ProcessingView(model: model)
                        case .result: ResultsView(model: model)
                        }
                    }
                    .toolbar {
                        if model.flow == .review || model.flow == .result {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { Task { await model.navigate(.home) } } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("Close").disabled(model.busy)
                            }
                        }
                    }
                    .toolbar(model.flow == .home || model.flow == .camera ? .hidden : .visible, for: .navigationBar)
                }
            }
        }
        .sheet(item: $model.sheet, onDismiss: { model.clearHistory() }) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .saved: HistoryView(model: model)
                    case .account: AccountView(model: model)
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { model.sheet = nil } } }
            }
            .presentationDragIndicator(.visible)
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onChange(of: model.signedIn) { _, signedIn in if !signedIn { camera.stop() } }
    }
}
