import SwiftUI
import AnixartKit

@main
struct AnixartApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    // Config first: it can move the API host before anything is fetched.
                    await environment.session.loadRemoteConfiguration()
                    await environment.session.restore()
                }
        }
    }
}
