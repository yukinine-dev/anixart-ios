import AVFoundation
import AVKit
import Foundation
import Observation
import UIKit
import os

/// Quality as the Android dialog lists it. Anixart hands over one URL per
/// episode, so for an HLS stream this picks a variant by capping the bitrate,
/// and for a single progressive file only "Авто" is meaningful.
enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case auto, p360, p480, p720, p1080

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Авто"
        case .p360: return "360p"
        case .p480: return "480p"
        case .p720: return "720p"
        case .p1080: return "1080p"
        }
    }

    /// Rough ceilings per rung, in bits per second; `0` means no cap.
    var peakBitRate: Double {
        switch self {
        case .auto: return 0
        case .p360: return 800_000
        case .p480: return 1_500_000
        case .p720: return 3_000_000
        case .p1080: return 6_000_000
        }
    }
}

/// State behind the built-in player.
@MainActor
@Observable
final class EmbeddedPlayerModel {
    private static let log = Logger(subsystem: "app.anixart.client", category: "player")

    /// The speeds the Android menu offers. "Обычн." is 1x.
    static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    static func label(for rate: Float) -> String {
        rate == 1 ? "Обычн." : String(format: "%g×", rate)
    }

    let player = AVPlayer()

    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var duration: TimeInterval = 0
    private(set) var position: TimeInterval = 0
    private(set) var rate: Float = 1
    private(set) var quality: VideoQuality = .auto
    private(set) var isEnhanced = false
    private(set) var isLocked = false
    private(set) var areControlsVisible = true
    private(set) var seekFeedback: String?

    var isFilling = false

    /// Where the slider sits: the scrub target while dragging, playback otherwise.
    private(set) var scrubPosition: TimeInterval = 0
    private var isScrubbing = false

    // None of these drive the UI, and `adopt(playerLayer:)` runs while the view
    // is being made, where writing an observed property would warn.
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var bufferObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var hideControlsTask: Task<Void, Never>?
    @ObservationIgnored private var seekFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?

    @ObservationIgnored private var onProgress: ((TimeInterval) -> Void)?
    @ObservationIgnored private var onFinished: (() -> Void)?
    @ObservationIgnored private var hasReportedFinish = false
    @ObservationIgnored private var asset: AVURLAsset?

    var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - Lifecycle

    func start(
        url: URL,
        startAt: TimeInterval?,
        onProgress: @escaping (TimeInterval) -> Void,
        onFinished: @escaping () -> Void
    ) async {
        guard asset == nil else { return }
        self.onProgress = onProgress
        self.onFinished = onFinished

        // Several hostings refuse a request without a Referer, the same way they
        // do for the web player.
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["Referer": AnixartEnvironment.webBaseURL.absoluteString]
        ])
        self.asset = asset

        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        observe(item)

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        if let startAt, startAt > 1 {
            await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        scheduleControlsHide()
    }

    func stop() {
        report()
        player.pause()
        isPlaying = false
        hideControlsTask?.cancel()
        seekFeedbackTask?.cancel()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation = nil
        bufferObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if !self.isScrubbing { self.scrubPosition = self.position }
                self.reportIfFinished()
            }
        }

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            let failure = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if status == .readyToPlay {
                    self.duration = seconds.isFinite ? seconds : 0
                    self.isBuffering = false
                } else if status == .failed {
                    Self.log.error("playback failed: \(failure ?? "unknown", privacy: .public)")
                    self.isBuffering = false
                }
            }
        }

        bufferObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let keepsUp = item.isPlaybackLikelyToKeepUp
            Task { @MainActor [weak self] in
                self?.isBuffering = !keepsUp
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.finish()
            }
        }
    }

    // MARK: - Transport

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
            player.rate = rate
        }
        isPlaying.toggle()
        scheduleControlsHide()
    }

    func seek(by offset: TimeInterval) {
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, position + offset))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        position = target
        scrubPosition = target
        showSeekFeedback(offset >= 0 ? "+\(Int(offset)) с" : "\(Int(offset)) с")
        scheduleControlsHide()
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if !scrubbing {
            player.seek(to: CMTime(seconds: scrubPosition, preferredTimescale: 600))
            position = scrubPosition
        }
        scheduleControlsHide()
    }

    func scrub(to value: TimeInterval) {
        scrubPosition = value
    }

    func setRate(_ newRate: Float) {
        // The enhanced picture is composed frame by frame, so the explainer caps
        // the speed at 1.5x; honour that rather than dropping frames.
        rate = isEnhanced ? min(newRate, 1.5) : newRate
        if isPlaying { player.rate = rate }
        scheduleControlsHide()
    }

    func setQuality(_ newQuality: VideoQuality) {
        quality = newQuality
        player.currentItem?.preferredPeakBitRate = newQuality.peakBitRate
        scheduleControlsHide()
    }

    func setEnhancement(_ enabled: Bool) {
        guard enabled != isEnhanced else { return }
        isEnhanced = enabled

        if enabled {
            isFilling = false
            if rate > 1.5 { setRate(1.5) }
            Task { [weak self] in
                guard let self, let asset = self.asset, let item = self.player.currentItem else { return }
                let composition = await VideoEnhanceFilter.videoComposition(for: asset)
                guard self.isEnhanced else { return }
                if composition == nil {
                    // Streamed assets have no composable tracks; say so rather
                    // than leaving a toggle on that changes nothing.
                    Self.log.notice("enhancement unavailable for this stream")
                    self.isEnhanced = false
                }
                item.videoComposition = composition
            }
        } else {
            player.currentItem?.videoComposition = nil
        }
        scheduleControlsHide()
    }

    // MARK: - Chrome

    func toggleControls() {
        areControlsVisible.toggle()
        if areControlsVisible { scheduleControlsHide() }
    }

    func toggleLock() {
        isLocked.toggle()
        areControlsVisible = true
        scheduleControlsHide()
    }

    /// PiP needs the layer the picture is actually on, and the view owns that,
    /// so the view hands it over when it is created.
    func adopt(playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        pictureInPicture = AVPictureInPictureController(playerLayer: playerLayer)
    }

    func startPictureInPicture() {
        pictureInPicture?.startPictureInPicture()
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.areControlsVisible = false
        }
    }

    private func showSeekFeedback(_ text: String) {
        seekFeedback = text
        seekFeedbackTask?.cancel()
        seekFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.seekFeedback = nil
        }
    }

    // MARK: - Progress

    private func report() {
        guard position > 0 else { return }
        onProgress?(position)
    }

    /// Treats 90% as watched, as most players do -- the credits are not the point.
    private func reportIfFinished() {
        guard !hasReportedFinish, duration > 0, position / duration > 0.9 else { return }
        finish()
    }

    private func finish() {
        guard !hasReportedFinish else { return }
        hasReportedFinish = true
        onFinished?()
    }
}
