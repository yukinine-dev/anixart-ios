import SwiftUI
import UIKit
import AnixartKit

@main
@MainActor
struct AnixartApp: App {
    @State private var environment = AppEnvironment()

    init() {
        AppFont.applyToUIKitBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .anixartTypography()
                .task {
                    // Config first: it can move the API host before anything is fetched.
                    await environment.session.loadRemoteConfiguration()
                    await environment.session.restore()
                }
        }
    }
}
