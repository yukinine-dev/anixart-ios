import AVFoundation
import AVKit
import Foundation
import Observation
import UIKit
import os
import AnixartKit

/// One rung in the quality menu, built from what the stream actually offers
/// rather than from a fixed list.
///
/// There are two shapes. A single HLS playlist declares its own variants, and
/// switching between them is a bitrate ceiling. A source that publishes one
/// playlist per quality -- which is how AniLibria hands them over -- gives a
/// rung its own URL, and switching means swapping the item.
struct VideoQuality: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Ceiling handed to AVPlayer; `0` lets it choose.
    let peakBitRate: Double
    /// Set when this rung is its own playlist rather than a variant inside one.
    let url: URL?

    static let auto = VideoQuality(id: "auto", title: "Авто", peakBitRate: 0)

    /// "1080p" from a variant's presentation size, falling back to its bitrate
    /// when the playlist does not declare one.
    init(variant: AVAssetVariant) {
        let height = variant.videoAttributes?.presentationSize.height ?? 0
        let bitRate = variant.peakBitRate ?? variant.averageBitRate ?? 0
        self.peakBitRate = bitRate
        self.url = nil
        if height > 0 {
            self.title = "\(Int(height))p"
            self.id = "h\(Int(height))"
        } else {
            self.title = String(format: "%.1f Мбит/с", bitRate / 1_000_000)
            self.id = "b\(Int(bitRate))"
        }
    }

    init(id: String, title: String, peakBitRate: Double, url: URL? = nil) {
        self.id = id
        self.title = title
        self.peakBitRate = peakBitRate
        self.url = url
    }

    /// A rung a stream source published as its own playlist.
    init(stream: StreamVariant) {
        self.id = stream.id
        self.title = stream.label
        self.peakBitRate = 0
        self.url = stream.url
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
    private(set) var playbackError: String?
    private(set) var duration: TimeInterval = 0
    private(set) var position: TimeInterval = 0
    private(set) var rate: Float = 1
    private(set) var quality: VideoQuality = .auto
    /// What this stream actually offers. One entry means there is nothing to
    /// choose, and the view hides the menu rather than pretending otherwise.
    private(set) var qualities: [VideoQuality] = [.auto]
    /// Set when the enhancement could not be applied, so the toggle silently
    /// turning itself off is explained.
    private(set) var enhancementNote: String?
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
    @ObservationIgnored private var failedEndObserver: NSObjectProtocol?
    @ObservationIgnored private var hideControlsTask: Task<Void, Never>?
    @ObservationIgnored private var seekFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?

    @ObservationIgnored private var onProgress: ((TimeInterval) -> Void)?
    @ObservationIgnored private var onFinished: (() -> Void)?
    @ObservationIgnored private var hasReportedFinish = false
    @ObservationIgnored private var asset: AVURLAsset?
    @ObservationIgnored private var referer: URL?
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private var retryPosition: TimeInterval = 0
    /// Where to land once a replacement item is ready, during a quality change or retry.
    @ObservationIgnored private var pendingSeek: CMTime?
    @ObservationIgnored private var isSeekingReplacement = false
    @ObservationIgnored private var resumeAfterSeek = false
    /// Owns itself for as long as the tap is attached (see `AudioImpactTap`); kept
    /// here too so a quality change or retry can simply be handed a fresh one.
    @ObservationIgnored private var audioImpactTap: AudioImpactTap?

    private var hasPendingSeek: Bool { pendingSeek != nil }

    var canRetry: Bool { playbackError != nil && asset != nil && !isStopped }

    var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - Lifecycle

    func start(
        variants: [StreamVariant],
        referer: URL?,
        startAt: TimeInterval?,
        onProgress: @escaping (TimeInterval) -> Void,
        onFinished: @escaping () -> Void
    ) async {
        guard !isStopped, asset == nil else { return }
        self.onProgress = onProgress
        self.onFinished = onFinished
        self.referer = referer

        guard let first = variants.first else {
            playbackError = "Источник не вернул ссылку на видео. Откройте веб-плеер или выберите другой источник."
            isBuffering = false
            areControlsVisible = true
            return
        }

        if let startAt, startAt.isFinite, startAt > 1 {
            retryPosition = startAt
            position = startAt
            scrubPosition = startAt
            pendingSeek = CMTime(seconds: startAt, preferredTimescale: 600)
            resumeAfterSeek = true
        }

        let item = install(first.url)

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        guard canContinuePlayback(with: item) else { return }
        isPlaying = true
        if !hasPendingSeek { player.play() }
        applyRate()
        scheduleControlsHide()

        if variants.count > 1 {
            // A source that publishes one playlist per quality decides the menu
            // itself; there is no ladder inside the playlist to read.
            qualities = variants.map(VideoQuality.init(stream:))
            quality = qualities[0]
        } else if let asset {
            await loadQualities(from: asset)
        }
    }

    /// Points the player at one URL, keeping the observations attached to the
    /// item that is actually playing.
    @discardableResult
    private func install(_ url: URL) -> AVPlayerItem {
        // Several hostings refuse a request without a Referer, the same way they
        // do for the web player.
        let headers = ["Referer": (referer ?? AnixartEnvironment.webBaseURL).absoluteString]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        self.asset = asset

        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        observe(item)
        attachContentReactiveTapIfNeeded(to: item, asset: asset)
        return item
    }

    /// Reacting to the episode's own audio is a separate, explicit setting on
    /// top of "Плеер" -- someone may want the transport haptics above without
    /// their phone buzzing on every loud scene. Checked once, when the item is
    /// installed, not re-checked live while it plays.
    private func attachContentReactiveTapIfNeeded(to item: AVPlayerItem, asset: AVURLAsset) {
        audioImpactTap = nil
        guard AppHaptics.shared.isContentReactiveEnabled() else { return }
        let sensitivity = AppHaptics.shared.contentSensitivity()
        Task { [weak self] in
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty else { return }
            guard let self, !self.isStopped, self.player.currentItem === item else { return }
            self.audioImpactTap = AudioImpactTap.attach(to: item, tracks: tracks, sensitivity: sensitivity) { strength in
                Task { @MainActor in
                    AppHaptics.shared.play(.contentImpact(strength: strength))
                }
            }
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        report()
        player.pause()
        isPlaying = false
        isBuffering = false
        hideControlsTask?.cancel()
        seekFeedbackTask?.cancel()
        pendingSeek = nil
        isSeekingReplacement = false
        resumeAfterSeek = false
        audioImpactTap = nil
        detachObservations()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Reopens the same source, preserving the selected quality, speed and last position.
    func retry() {
        guard canRetry, let url = asset?.url else { return }
        player.pause()
        detachObservations()
        playbackError = nil
        isBuffering = true
        isPlaying = true
        pendingSeek = retryPosition > 0
            ? CMTime(seconds: retryPosition, preferredTimescale: 600) : nil
        isSeekingReplacement = false
        resumeAfterSeek = hasPendingSeek
        install(url)
        player.currentItem?.preferredPeakBitRate = quality.peakBitRate
        if !hasPendingSeek { player.play() }
        applyRate()
        scheduleControlsHide()
    }

    /// Both AVFoundation failure callbacks use this; stale items must not break a retry.
    func handlePlaybackFailure(_ message: String?, for item: AVPlayerItem) {
        guard !isStopped, player.currentItem === item, playbackError == nil else { return }
        let currentPosition = player.currentTime().seconds
        if let seconds = pendingSeek?.seconds, seconds.isFinite, seconds >= 0 {
            retryPosition = seconds
        } else if currentPosition.isFinite, currentPosition > 0 {
            retryPosition = currentPosition
        } else if position > 0 {
            retryPosition = position
        }
        let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = detail.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Источник не удалось воспроизвести. Попробуйте ещё раз или откройте веб-плеер."
        playbackError = description
        AppHaptics.shared.play(.error)
        Self.log.error("playback failed: \(description, privacy: .public)")
        player.pause()
        isPlaying = false
        isBuffering = false
        isScrubbing = false
        pendingSeek = nil
        isSeekingReplacement = false
        resumeAfterSeek = false
        hideControlsTask?.cancel()
        seekFeedbackTask?.cancel()
        seekFeedback = nil
        areControlsVisible = true
    }

    private func canContinuePlayback(with item: AVPlayerItem) -> Bool {
        guard !isStopped, player.currentItem === item, playbackError == nil else { return false }
        if item.status == .failed {
            handlePlaybackFailure(item.error?.localizedDescription, for: item)
            return false
        }
        return true
    }

    /// Lets go of the item that is being replaced or put away. Each `install`
    /// attaches its own, so they have to come off first or they stack up.
    private func detachObservations() {
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
        if let failedEndObserver {
            NotificationCenter.default.removeObserver(failedEndObserver)
            self.failedEndObserver = nil
        }
    }

    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped, self.player.currentItem === item,
                      self.playbackError == nil, !self.hasPendingSeek else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                self.retryPosition = self.position
                if !self.isScrubbing { self.scrubPosition = self.position }
                self.reportIfFinished()
            }
        }

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            let failure = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped, self.player.currentItem === item else { return }
                if status == .readyToPlay {
                    guard self.playbackError == nil else { return }
                    self.duration = seconds.isFinite ? seconds : 0
                    // The smoke test greps for this: it is the only line that
                    // says AVFoundation actually opened the stream.
                    Self.log.notice("playback ready, duration \(Int(self.duration), privacy: .public)s")
                    if self.hasPendingSeek {
                        await self.finishPendingSeek(for: item)
                    } else {
                        self.isBuffering = false
                    }
                } else if status == .failed {
                    self.handlePlaybackFailure(failure, for: item)
                }
            }
        }

        bufferObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let keepsUp = item.isPlaybackLikelyToKeepUp
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped, self.player.currentItem === item,
                      self.playbackError == nil, !self.hasPendingSeek else { return }
                self.isBuffering = !keepsUp
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped, self.player.currentItem === item,
                      self.playbackError == nil else { return }
                self.isPlaying = false
                self.finish()
            }
        }

        failedEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                self?.handlePlaybackFailure(error?.localizedDescription, for: item)
            }
        }
    }

    // MARK: - Transport

    func togglePlayback() {
        guard !isStopped, playbackError == nil else { return }
        AppHaptics.shared.play(.playbackToggled)
        isPlaying.toggle()
        if hasPendingSeek {
            resumeAfterSeek = isPlaying
            if !isPlaying { player.pause() }
        } else if isPlaying {
            player.play()
            applyRate()
        } else {
            player.pause()
        }
        scheduleControlsHide()
    }

    func seek(by offset: TimeInterval, isIntroSkip: Bool = false) {
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, position + offset))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        position = target
        retryPosition = target
        scrubPosition = target
        showSeekFeedback(offset >= 0 ? "+\(Int(offset)) с" : "\(Int(offset)) с")
        AppHaptics.shared.play(isIntroSkip ? .introSkipped : .seekTick)
        scheduleControlsHide()
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if !scrubbing {
            player.seek(to: CMTime(seconds: scrubPosition, preferredTimescale: 600))
            position = scrubPosition
            retryPosition = scrubPosition
        }
        scheduleControlsHide()
    }

    func scrub(to value: TimeInterval) {
        scrubPosition = value
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        applyRate()
        scheduleControlsHide()
    }

    /// `play()` resets the rate to `defaultRate`, and AVPlayer calls it itself
    /// when a stall clears -- so setting `rate` alone let the speed fall back to
    /// 1x on its own. Both are set, which is what makes a chosen speed stick.
    private func applyRate() {
        player.defaultRate = rate
        if isPlaying, !hasPendingSeek { player.rate = rate }
    }

    func setQuality(_ newQuality: VideoQuality) {
        guard !isStopped, playbackError == nil, newQuality != quality else { return }
        quality = newQuality

        guard let url = newQuality.url else {
            player.currentItem?.preferredPeakBitRate = newQuality.peakBitRate
            scheduleControlsHide()
            return
        }

        // Its own playlist, so the item is replaced and the position carried
        // over. The seek has to wait for the new item to be ready -- seeking a
        // fresh item before that silently lands wherever it can.
        let current = player.currentTime()
        pendingSeek = pendingSeek ?? (current.seconds.isFinite && current.seconds >= 0
            ? current : CMTime(seconds: retryPosition, preferredTimescale: 600))
        isSeekingReplacement = false
        resumeAfterSeek = isPlaying
        isBuffering = true
        player.pause()
        detachObservations()
        install(url)
        scheduleControlsHide()
    }

    /// Puts the new playlist back at the position the old one was at.
    ///
    /// The tolerances are both zero on purpose. A default seek is allowed to
    /// land on the nearest segment boundary, which on an HLS stream is several
    /// seconds earlier -- so changing quality visibly rewound the episode.
    /// Exact seeking takes longer and is what the buffering spinner is for.
    private func finishPendingSeek(for item: AVPlayerItem) async {
        guard let target = pendingSeek, !isSeekingReplacement else { return }
        isSeekingReplacement = true

        // Keep the target until completion: a failure during this await must
        // retry it, not the new item's initial zero-second position.
        let completed = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        guard canContinuePlayback(with: item) else { return }
        pendingSeek = nil
        isSeekingReplacement = false
        if completed {
            let seconds = player.currentTime().seconds
            position = seconds.isFinite ? seconds : position
            retryPosition = position
        }
        scrubPosition = position
        isBuffering = false

        if resumeAfterSeek {
            isPlaying = true
            player.play()
            applyRate()
        }
        resumeAfterSeek = false
    }

    /// Reads the rungs off the asset. An HLS playlist declares variants; a
    /// progressive file has none, so its own resolution is the only entry and
    /// the menu becomes a label.
    private func loadQualities(from asset: AVURLAsset) async {
        if let variants = try? await asset.load(.variants), !variants.isEmpty {
            guard !isStopped, self.asset === asset else { return }
            var rungs = variants.map(VideoQuality.init(variant:))
            // Several variants can share a height (different codecs); keep the
            // highest bitrate of each and sort tallest first.
            rungs = Dictionary(grouping: rungs, by: \.id)
                .compactMap { $0.value.max(by: { $0.peakBitRate < $1.peakBitRate }) }
                .sorted { $0.peakBitRate > $1.peakBitRate }
            qualities = [.auto] + rungs
            quality = .auto
            return
        }

        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize)
        else {
            guard !isStopped, self.asset === asset else { return }
            qualities = [.auto]
            return
        }
        guard !isStopped, self.asset === asset else { return }
        let height = Int(abs(size.height))
        let single = VideoQuality(id: "native", title: height > 0 ? "\(height)p" : "Исходное", peakBitRate: 0)
        qualities = [single]
        quality = single
    }

    func dismissEnhancementNote() {
        enhancementNote = nil
    }

    func setEnhancement(_ enabled: Bool) {
        guard enabled != isEnhanced else { return }

        if enabled, !VideoEnhanceFilter.isAvailable {
            enhancementNote = "Улучшение недоступно в этой сборке"
            scheduleControlsHide()
            return
        }

        isEnhanced = enabled
        // No speed cap any more. The Android explainer lists one because its GL
        // effect composed frames on the way through; `EnhancedVideoSurface`
        // draws whatever the player presents, at display rate, so a higher
        // playback speed costs it nothing per drawn frame.
        //
        // `EnhancedVideoSurface` draws the frames while this is on; nothing is
        // set on the item itself, because a video composition cannot touch an
        // HLS stream and HLS is all this player gets.
        scheduleControlsHide()
    }

    /// Called by the surface when it cannot draw at all, so the toggle does not
    /// stay on over a black screen.
    func reportEnhancementFailure(_ message: String) {
        guard isEnhanced else { return }
        isEnhanced = false
        enhancementNote = message
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
        guard !isStopped, playbackError == nil else { return }
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
        AppHaptics.shared.play(.episodeFinished)
        onFinished?()
    }
}
