import SwiftUI

@main
struct AiveraEchoApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .tint(.echoAccent)
        }
    }
}
