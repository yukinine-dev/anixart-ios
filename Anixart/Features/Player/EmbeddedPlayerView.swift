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
                .onTapGesture { model.toggleControls() }

            if model.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if model.areControlsVisible {
                controls
                    .transition(.opacity)
            } else if model.isLocked {
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
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // The Android player is landscape; ask for it rather than forcing it, so
        // a device with rotation locked still plays.
        .onAppear { Orientation.request(.landscape) }
        .onDisappear { Orientation.request(.all) }
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
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            if !model.isLocked {
                Button {
                    model.stop()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left").font(.ax(.title3))
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
        .padding(.vertical, 12)
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
                // The explainer caps the enhanced picture at 1.5x.
                .disabled(model.isEnhanced && speed > 1.5)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                Text(EmbeddedPlayerModel.label(for: model.rate)).font(.ax(.subheadline))
                Image(systemName: "chevron.down").font(.ax(.caption))
            }
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
        }
    }

    private var lockButton: some View {
        Button {
            model.toggleLock()
        } label: {
            Image(systemName: model.isLocked ? "lock.fill" : "lock.open")
                .font(.ax(.title3))
                .foregroundStyle(.white)
                .padding(8)
        }
    }

    private var centreControls: some View {
        HStack(spacing: 48) {
            Button { model.seek(by: -10) } label: {
                Image(systemName: "gobackward.10").font(.ax(fixed: 34))
            }
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.ax(fixed: 44))
            }
            Button { model.seek(by: 10) } label: {
                Image(systemName: "goforward.10").font(.ax(fixed: 34))
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

            HStack {
                Text("\(Format.duration(model.scrubPosition)) / \(Format.duration(model.duration))")
                    .font(.ax(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Spacer()

                if !model.isLocked {
                    Button {
                        model.seek(by: TimeInterval(preferences.rewindSeconds))
                    } label: {
                        Image(systemName: "forward.fill").font(.ax(.title3))
                    }
                    .help("Пропустить заставку")

                    Button { model.startPictureInPicture() } label: {
                        Image(systemName: "pip.enter").font(.ax(.title3))
                    }
                    .disabled(!model.isPictureInPictureSupported)

                    Button { model.isFilling.toggle() } label: {
                        Image(systemName: model.isFilling
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.ax(.title3))
                    }
                    // The enhanced picture is composed at the video's own size,
                    // so scaling it is the limitation the explainer names.
                    .disabled(model.isEnhanced)
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
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
                    limitation("Недоступно масштабирование видео")
                    limitation("Скорость воспроизведения до 1.5x")
                    limitation("Повышенный расход батареи")
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

/// Asks the scene for an orientation. iOS 16 replaced the old
/// `UIDevice.setValue(_:forKey:)` trick with this, and a refusal is fine -- the
/// player works either way.
@MainActor
enum Orientation {
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
