import SwiftUI

/// These names and the 96pt centered mark also appear in LaunchScreen.storyboard.
/// The neutral adaptive background intentionally matches the system launch screen;
/// account/device themes are applied by RootView once actual content is ready.
enum AppLaunchPresentation {
    static let markName = "LaunchMark"
    static let backgroundName = "LaunchBackground"
    static let markSide: CGFloat = 96

    static func motionPolicy(reduceMotion: Bool, resourceSaving: Bool, lowPower: Bool) -> AppMotionPolicy {
        AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving || lowPower)
    }
}

@MainActor
struct AppLaunchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var revealAnimation: Animation? {
        AppLaunchPresentation.motionPolicy(
            reduceMotion: reduceMotion, resourceSaving: resourceSaving, lowPower: lowPower
        ).animation
    }

    var body: some View {
        ZStack {
            // Never mount Home (or a smoke screen) under the initial loading view:
            // its view tasks would race configuration and duplicate the warm load.
            if env.launch.isReady {
                RootView().transition(.identity)
            }
            if !env.launch.isReady {
                AppLaunchLoadingScreen()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(revealAnimation, value: env.launch.isReady)
        .task { await env.launch.startIfNeeded() }
        .onChange(of: env.session.viewerKey) { _, viewer in
            env.launch.discardPrewarmedFeed(ifViewerChangedTo: viewer)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// Static state feedback, with no timer, spinner, pulse or decorative loop. The
/// original icon is a normal named asset so UIKit's native launch and SwiftUI use
/// the same bytes rather than trying to load an appiconset as an ordinary image.
struct AppLaunchLoadingScreen: View {
    var body: some View {
        Image(AppLaunchPresentation.markName)
            .resizable()
            .scaledToFit()
            .frame(width: AppLaunchPresentation.markSide, height: AppLaunchPresentation.markSide)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(AppLaunchPresentation.backgroundName))
            .ignoresSafeArea()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Anixart")
            .accessibilityValue("Загрузка")
    }
}
