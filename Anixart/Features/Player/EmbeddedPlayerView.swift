import AVFoundation
import AVKit
import SwiftUI
import UIKit
import AnixartKit

/// The built-in player, laid out as the Android one: back, title and episode on
/// the left of the top bar; speed, quality and the lock on the right; a scrubber
/// with the elapsed/total time, the skip-intro button, picture in picture and
/// the fill toggle along the bottom.
@MainActor
struct EmbeddedPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    /// Every quality the stream was offered at, tallest first.
    let variants: [StreamVariant]
    /// Some hosts refuse a request without one.
    let referer: URL?
    /// Named under the episode when the stream came from somewhere other than
    /// the hosting the user picked.
    let streamSourceName: String?
    let releaseTitle: String
    let episodeTitle: String
    let startAt: TimeInterval?
    let preferences: PlaybackPreferences
    let onProgress: (TimeInterval) -> Void
    let onFinished: () -> Void
    var onWebFallback: (() -> Void)? = nil

    @State private var model = EmbeddedPlayerModel()
    @State private var isShowingEnhanceExplainer = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface(
                player: model.player,
                isFilling: model.isFilling,
                onLayerReady: { model.adopt(playerLayer: $0) }
            )
            .ignoresSafeArea()

            // Over the player layer, not instead of it: the layer keeps
            // decoding, keeps the audio and keeps picture in picture working.
            if model.isEnhanced, model.playbackError == nil {
                EnhancedVideoSurface(
                    player: model.player,
                    isFilling: model.isFilling,
                    strength: preferences.enhanceStrength,
                    onFailure: { model.reportEnhancementFailure($0) }
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            Color.clear
                .contentShape(.rect)
                .ignoresSafeArea()
                .onTapGesture { model.toggleControls() }

            if model.isBuffering, model.playbackError == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if model.playbackError == nil, model.areControlsVisible {
                controls
                    .transition(.opacity)
            } else if model.playbackError == nil, model.isLocked {
                // Locked still needs a way out, so the padlock stays reachable.
                lockButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding()
            }

            if let note = model.enhancementNote {
                Text(note)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        model.dismissEnhancementNote()
                    }
            }

            if let seek = model.seekFeedback {
                Text(seek)
                    .font(.ax(.title3, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: Capsule())
            }

            if let error = model.playbackError {
                playbackError(error)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // The Android player is landscape; ask for it rather than forcing it, so
        // a device with rotation locked still plays.
        .onAppear { Orientation.pin(.landscape) }
        .onDisappear { Orientation.pin(.all) }
        // The padlock is an orientation lock as well as a control lock, which is
        // what it is in the Android player: once it is on, tilting the phone
        // must not turn the picture.
        .onChange(of: model.isLocked) { _, locked in
            Orientation.pin(locked ? Orientation.currentMask : .landscape)
        }
        .sheet(isPresented: $isShowingEnhanceExplainer) {
            VideoEnhanceExplainer {
                preferences.markEnhanceExplained()
                model.setEnhancement(true)
            }
        }
        .task {
            await model.start(
                variants: variants,
                referer: referer,
                startAt: startAt,
                onProgress: onProgress,
                onFinished: onFinished
            )
        }
        .onDisappear { model.stop() }
    }

    private func playbackError(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.ax(fixed: 36))
                Text("Не удалось воспроизвести видео")
                    .font(.ax(.title3, .medium))
                Text(message)
                    .font(.ax(.body))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Попробовать снова") { model.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(!model.canRetry)
                    .accessibilityIdentifier("player.retry")

                if let onWebFallback {
                    Button("Открыть веб-плеер") {
                        model.stop()
                        onWebFallback()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityIdentifier("player.webFallback")
                }
                Button("Закрыть") {
                    model.stop()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityIdentifier("player.closeError")
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: 480)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.9).ignoresSafeArea())
        .accessibilityIdentifier("player.error")
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if !model.isLocked { centreControls }
            Spacer()
            bottomBar
        }
        .background(
            // This gradient covers the whole screen, so it -- not the video
            // underneath -- is what a tap on empty space actually hits. Without
            // the gesture here the chrome could only be dismissed by waiting.
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture { model.toggleControls() }
        )
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 22) {
            if !model.isLocked {
                Button {
                    model.stop()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left").font(.ax(.title3)).playerHitArea()
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(releaseTitle).font(.ax(.title3)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(episodeTitle)
                        // The hosting Anixart named rarely hands over the video
                        // itself, so say where this picture is coming from.
                        if let streamSourceName {
                            Text("· \(streamSourceName)")
                        }
                    }
                    .font(.ax(.subheadline))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if !model.isLocked {
                speedMenu
                qualityMenu
            }
            lockButton
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(EmbeddedPlayerModel.speeds, id: \.self) { speed in
                Button {
                    model.setRate(speed)
                } label: {
                    if model.rate == speed {
                        Label(EmbeddedPlayerModel.label(for: speed), systemImage: "checkmark")
                    } else {
                        Text(EmbeddedPlayerModel.label(for: speed))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                Text(EmbeddedPlayerModel.label(for: model.rate)).font(.ax(.subheadline))
                Image(systemName: "chevron.down").font(.ax(.caption))
            }
            .playerHitHeight()
        }
    }

    private var qualityMenu: some View {
        Menu {
            // Only what the stream actually offers. A progressive file has a
            // single encode, so there is nothing to pick and the menu just
            // reports its resolution.
            if model.qualities.count > 1 {
                Picker("Качество", selection: Binding(
                    get: { model.quality },
                    set: { model.setQuality($0) }
                )) {
                    ForEach(model.qualities) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            } else {
                Text("Качество: \(model.quality.title)")
            }

            if VideoEnhanceFilter.isAvailable {
                Divider()
                Button {
                    if model.isEnhanced {
                        model.setEnhancement(false)
                    } else if preferences.hasSeenEnhanceExplainer {
                        model.setEnhancement(true)
                    } else {
                        isShowingEnhanceExplainer = true
                    }
                } label: {
                    Label(
                        "Режим улучшения видео +",
                        systemImage: model.isEnhanced ? "checkmark.circle.fill" : "wand.and.stars"
                    )
                }

                if model.isEnhanced {
                    // How sharp is too sharp is a matter of taste, and the only
                    // way to settle it is to change it while watching.
                    Picker("Сила улучшения", selection: Binding(
                        get: { preferences.enhanceStrength },
                        set: { preferences.setEnhanceStrength($0) }
                    )) {
                        ForEach(VideoEnhanceFilter.Strength.available) { level in
                            Text(level.title).tag(level)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("HQ")
                    .font(.ax(.caption2, .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.black)
                Text(model.quality.title).font(.ax(.subheadline))
                Image(systemName: "chevron.down").font(.ax(.caption))
            }
            .playerHitHeight()
        }
    }

    private var lockButton: some View {
        Button {
            model.toggleLock()
        } label: {
            Image(systemName: model.isLocked ? "lock.fill" : "lock.open")
                .font(.ax(.title3))
                .foregroundStyle(.white)
                .playerHitArea()
        }
    }

    private var centreControls: some View {
        HStack(spacing: 56) {
            Button { model.seek(by: -10) } label: {
                Image(systemName: "gobackward.10").font(.ax(fixed: 34)).playerHitArea(64)
            }
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.ax(fixed: 44))
                    .playerHitArea(72)
            }
            Button { model.seek(by: 10) } label: {
                Image(systemName: "goforward.10").font(.ax(fixed: 34)).playerHitArea(64)
            }
        }
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { model.scrubPosition },
                    set: { model.scrub(to: $0) }
                ),
                in: 0...max(model.duration, 1),
                onEditingChanged: { model.setScrubbing($0) }
            )
            .tint(.white)
            .disabled(model.isLocked)

            HStack(spacing: 20) {
                Text("\(Format.duration(model.scrubPosition)) / \(Format.duration(model.duration))")
                    .font(.ax(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Spacer()

                if !model.isLocked {
                    Button {
                        model.seek(by: TimeInterval(preferences.rewindSeconds))
                    } label: {
                        Image(systemName: "forward.fill").font(.ax(.title3)).playerHitArea()
                    }
                    .help("Пропустить заставку")

                    Button { model.startPictureInPicture() } label: {
                        Image(systemName: "pip.enter").font(.ax(.title3)).playerHitArea()
                    }
                    .disabled(!model.isPictureInPictureSupported)

                    // Enabled while enhanced too: the Metal surface applies the
                    // same geometry the player layer does, so there is nothing
                    // left for this to break.
                    Button { model.isFilling.toggle() } label: {
                        Image(systemName: model.isFilling
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.ax(.title3))
                            .playerHitArea()
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}

extension View {
    /// Gives a player control a real target.
    ///
    /// These were all the size of their own glyph, which is a small thing to hit
    /// on a moving picture; 48pt is above the 44pt minimum and the extra also
    /// opens the gaps between them up.
    func playerHitArea(_ side: CGFloat = 48) -> some View {
        frame(minWidth: side, minHeight: side)
            .contentShape(.rect)
    }

    /// For a control that is already wide enough -- a menu with a text label --
    /// where only the height and the tappable shape need opening up.
    func playerHitHeight(_ side: CGFloat = 48) -> some View {
        frame(minHeight: side)
            .contentShape(.rect)
    }
}

/// The explainer the Android player shows before the enhancement is first used.
@MainActor
struct VideoEnhanceExplainer: View {
    @Environment(\.dismiss) private var dismiss
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Режим улучшения видео +")
                    .font(.ax(.title2, .medium))
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Этот режим улучшает качество изображения, делая картинку более чёткой и детализированной.")
                    .font(.ax(.title3))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    benefit("Устраняет мыльность картинки")
                    benefit("Подчёркивает контурные линии")
                }

                Text("Ограничения:")
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    // The Android list also caps the speed at 1.5x and
                    // disables zoom, because its GL effect composed frames on
                    // the way through. This one draws what the player presents,
                    // so neither holds here and claiming them would be wrong.
                    limitation("Повышенный расход батареи")
                    limitation("Требуется поддержка Metal")
                }

                Button {
                    onAccept()
                    dismiss()
                } label: {
                    Text("Понятно")
                        .font(.ax(.title3, .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.primary.opacity(0.9), in: Capsule())
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }

    private func benefit(_ text: String) -> some View {
        Label {
            Text(text).font(.ax(.title3))
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.listColor(.watching))
        }
    }

    private func limitation(_ text: String) -> some View {
        Label {
            Text(text).font(.ax(.title3))
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.listColor(.holdOn))
        }
    }
}

/// `AVPlayerLayer` under SwiftUI. `VideoPlayer` brings Apple's own controls,
/// which is the one thing this screen must not have.
@MainActor
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var isFilling: Bool
    var onLayerReady: (AVPlayerLayer) -> Void

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.backgroundColor = .black
        onLayerReady(view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = isFilling ? .resizeAspectFill : .resizeAspect
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Holds the interface to an orientation.
///
/// `requestGeometryUpdate` only rotates once. The moment the device is tilted,
/// the window's own supported set -- everything the Info.plist lists, portrait
/// included -- takes over again, which is why the player kept dropping back to
/// portrait and why the padlock did not hold it. The system intersects the app
/// delegate's mask with the view controller's, so the delegate is the part that
/// actually restricts; the geometry request just performs the rotation.
@MainActor
enum Orientation {
    static func pin(_ mask: UIInterfaceOrientationMask) {
        OrientationGate.mask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }

    /// Just the orientation on screen right now, which is what the padlock pins
    /// to: locking should keep what the user is holding, not pick for them.
    static var currentMask: UIInterfaceOrientationMask {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}

/// The app delegate exists only to answer the orientation question.
///
/// A SwiftUI app has no view controller of its own to override, and this is the
/// one hook the system consults before the window's.
final class OrientationGate: NSObject, UIApplicationDelegate {
    // Read and written on the main actor only -- UIKit asks on the main thread
    // and `Orientation.pin` is main-actor isolated.
    nonisolated(unsafe) static var mask: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.mask
    }
}
