import SwiftUI

@main
struct ArtIflowApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var speech = SpeechRecognizer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(speech)
                .preferredColorScheme(.light)
        }
    }
}
