import SwiftUI

@main struct PersonalStylistApp: App {
    @State private var model = AppModel.makeDefault()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(StylistTheme.accent)
                .preferredColorScheme(.light)
        }
    }
}
