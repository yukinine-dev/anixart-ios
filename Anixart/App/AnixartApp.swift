import SwiftUI
import UIKit
import AnixartKit

@main
@MainActor
struct AnixartApp: App {
    // Only there to answer the orientation question: the player pins landscape,
    // and the padlock pins whichever way the phone is being held.
    @UIApplicationDelegateAdaptor(OrientationGate.self) private var orientationGate

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
