import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if model.starting {
                ProgressView("Preparing your private workspace…").frame(maxWidth: .infinity, maxHeight: .infinity).background(StylistTheme.background)
            } else if model.startupFailed {
                Page(title: "Private startup could not finish") {
                    NoticeView(error: model.error)
                    StylistButton(title: "Retry secure startup") { Task { await model.start() } }
                    StylistButton(title: "Clear local sign-in and retry", secondary: true) { Task { await model.resetStartup() } }.disabled(model.busy)
                }
            } else if !model.onboarded {
                NavigationStack {
                    OnboardingView(model: model)
                        .toolbar {
                            if model.signedIn { NavigationLink("Account") { AccountView(model: model) } }
                        }
                }
            } else {
                TabView(selection: $model.tab) {
                    NavigationStack {
                        Group {
                            switch model.flow {
                            case .home, .camera: HomeView(model: model)
                            case .review: ReviewView(model: model)
                            case .processing: ProcessingView(model: model)
                            case .result: ResultsView(model: model)
                            }
                        }
                        .toolbar {
                            if model.flow != .home && model.flow != .camera {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Close", systemImage: "xmark") { Task { await model.navigate(.home) } }.disabled(model.busy)
                                }
                            }
                        }
                        .toolbar(model.flow == .home ? .visible : .hidden, for: .tabBar)
                    }.tabItem { Label("Home", systemImage: "house") }.tag(AppModel.Tab.home)
                    NavigationStack { HistoryView(model: model) }.id(model.historyNavigationID).tabItem { Label("Saved", systemImage: "bookmark") }.tag(AppModel.Tab.saved)
                    NavigationStack { AccountView(model: model) }.tabItem { Label("Account", systemImage: "person.crop.circle") }.tag(AppModel.Tab.account)
                }
                .fullScreenCover(isPresented: Binding(get: { model.flow == .camera }, set: { if !$0 && model.flow == .camera { model.flow = .home } })) {
                    CameraView(model: model)
                }
                .onChange(of: model.tab) { previous, next in
                    if previous == .saved { model.clearHistory() }
                    if next != .home {
                        Task { do { try await model.clearAnalysis(); model.flow = .home } catch { model.error = error.localizedDescription } }
                    }
                }
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}
