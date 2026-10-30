import AVFoundation
import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class EmbeddedPlayerRecoveryTests: XCTestCase {
    @MainActor
    func testMissingLocalFileReportsFailureWithoutFinishing() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        let model = EmbeddedPlayerModel()
        var finishes = 0
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url, onFinished: { finishes += 1 })
        let item = try XCTUnwrap(model.player.currentItem)
        try await waitUntil("AVPlayer should fail on a missing local file") {
            item.status == .failed && model.playbackError != nil
        }

        XCTAssertFalse(try XCTUnwrap(model.playbackError).isEmpty)
        XCTAssertTrue(model.canRetry)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isBuffering)
        XCTAssertTrue(model.areControlsVisible)
        XCTAssertEqual(model.player.rate, 0)
        XCTAssertEqual(finishes, 0)
    }

    @MainActor
    func testRetryReopensSameURLAfterFileBecomesAvailable() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        let model = EmbeddedPlayerModel()
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url)
        try await waitUntil("The initial missing-file failure should be visible") {
            model.playbackError != nil
        }
        let failedItem = try XCTUnwrap(model.player.currentItem)

        try writeSilentWAV(to: url)
        model.retry()
        let replacement = try XCTUnwrap(model.player.currentItem)

        XCTAssertFalse(replacement === failedItem)
        XCTAssertEqual((replacement.asset as? AVURLAsset)?.url, url)
        try await waitForPlayback(model)
        try await waitUntil("Recovered playback should advance") {
            model.player.currentTime().seconds > 0.1
        }
        XCTAssertNil(model.playbackError)
        XCTAssertFalse(model.canRetry)
    }

    @MainActor
    func testRetryPreservesSelectedPlaylistSpeedAndPosition() async throws {
        let directory = try makeDirectory()
        let highURL = directory.appendingPathComponent("1080.wav")
        let lowURL = directory.appendingPathComponent("720.wav")
        try writeSilentWAV(to: highURL)
        try writeSilentWAV(to: lowURL)
        let model = EmbeddedPlayerModel()
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await model.start(
            variants: [StreamVariant(url: highURL, height: 1080), StreamVariant(url: lowURL, height: 720)],
            referer: nil,
            startAt: 5,
            onProgress: { _ in },
            onFinished: {}
        )
        try await waitForPlayback(model)
        model.setRate(1.5)
        let selectedQuality = try XCTUnwrap(model.qualities.last)
        model.setQuality(selectedQuality)
        try await waitForPlayback(model)
        model.togglePlayback()

        let failedItem = try XCTUnwrap(model.player.currentItem)
        let resumePosition = model.player.currentTime().seconds
        XCTAssertGreaterThanOrEqual(resumePosition, 5)
        postFailure(for: failedItem, message: "Source stopped during playback")
        XCTAssertNotNil(model.playbackError)

        model.retry()
        let replacement = try XCTUnwrap(model.player.currentItem)
        XCTAssertFalse(replacement === failedItem)
        XCTAssertEqual((replacement.asset as? AVURLAsset)?.url, lowURL)
        try await waitForPlayback(model)

        XCTAssertEqual(model.quality, selectedQuality)
        XCTAssertEqual(model.rate, 1.5)
        XCTAssertEqual(model.player.defaultRate, 1.5)
        XCTAssertEqual(model.player.rate, 1.5)
        XCTAssertEqual(model.player.currentTime().seconds, resumePosition, accuracy: 1)
        XCTAssertEqual(model.position, resumePosition, accuracy: 1)
    }

    @MainActor
    func testRetryPreservesBitrateCeiling() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        try writeSilentWAV(to: url)
        let model = EmbeddedPlayerModel()
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url)
        try await waitForPlayback(model)
        let quality = VideoQuality(id: "h720", title: "720p", peakBitRate: 2_000_000)
        model.setQuality(quality)
        postFailure(for: try XCTUnwrap(model.player.currentItem))

        model.retry()
        XCTAssertEqual(model.player.currentItem?.preferredPeakBitRate, quality.peakBitRate)
        try await waitForPlayback(model)
        XCTAssertEqual(model.quality, quality)
    }

    @MainActor
    func testRepeatedNativeFailuresKeepResumeTarget() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        let model = EmbeddedPlayerModel()
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url, startAt: 8)
        try await waitUntil("The first missing-file failure should be visible") {
            model.player.currentItem?.status == .failed && model.playbackError != nil
        }
        let firstItem = try XCTUnwrap(model.player.currentItem)
        model.retry()
        let secondItem = try XCTUnwrap(model.player.currentItem)
        XCTAssertFalse(secondItem === firstItem)
        try await waitUntil("Retrying the missing file should fail again") {
            secondItem.status == .failed && model.playbackError != nil
        }

        try writeSilentWAV(to: url)
        model.retry()
        try await waitForPlayback(model)
        XCTAssertEqual(model.player.currentTime().seconds, 8, accuracy: 1)
        XCTAssertEqual(model.position, 8, accuracy: 1)
    }

    @MainActor
    func testLateFailureAndEndEventsFromReplacedItemAreIgnored() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        try writeSilentWAV(to: url)
        let model = EmbeddedPlayerModel()
        var finishes = 0
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url, onFinished: { finishes += 1 })
        try await waitForPlayback(model)
        let oldItem = try XCTUnwrap(model.player.currentItem)
        postFailure(for: oldItem)
        model.retry()
        try await waitForPlayback(model)

        model.handlePlaybackFailure("Late callback from the old item", for: oldItem)
        postFailure(for: oldItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        await Task.yield()

        XCTAssertNil(model.playbackError)
        XCTAssertTrue(model.isPlaying)
        XCTAssertFalse(model.isBuffering)
        XCTAssertEqual(finishes, 0)
    }

    @MainActor
    func testFailedToEndReportsDetailsAndDoesNotFinishEpisode() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        try writeSilentWAV(to: url)
        let model = EmbeddedPlayerModel()
        var finishes = 0
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url, onFinished: { finishes += 1 })
        try await waitForPlayback(model)
        let item = try XCTUnwrap(model.player.currentItem)
        postFailure(for: item, message: "The source disconnected")

        XCTAssertEqual(model.playbackError, "The source disconnected")
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isBuffering)
        XCTAssertTrue(model.canRetry)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        XCTAssertEqual(finishes, 0)

        model.handlePlaybackFailure(nil, for: item)
        XCTAssertEqual(model.playbackError, "The source disconnected")
    }

    @MainActor
    func testFailureWithoutDetailsUsesReadableFallback() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        try writeSilentWAV(to: url)
        let model = EmbeddedPlayerModel()
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url)
        try await waitForPlayback(model)
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: try XCTUnwrap(model.player.currentItem)
        )

        XCTAssertTrue(try XCTUnwrap(model.playbackError).contains("Попробуйте ещё раз"))
        XCTAssertTrue(model.canRetry)
        XCTAssertFalse(model.isBuffering)
    }

    @MainActor
    func testStopDisablesRetryAndIgnoresLateCallbacks() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        let model = EmbeddedPlayerModel()
        var progressReports = 0
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await model.start(
            variants: [StreamVariant(url: url)],
            referer: nil,
            startAt: 8,
            onProgress: { _ in progressReports += 1 },
            onFinished: {}
        )
        try await waitUntil("The missing-file failure should be visible before stop") {
            model.playbackError != nil
        }
        let item = try XCTUnwrap(model.player.currentItem)
        let originalError = model.playbackError
        model.stop()
        model.stop()
        model.retry()
        model.handlePlaybackFailure("Late error after stop", for: item)
        postFailure(for: item)
        await start(model, url: url)

        XCTAssertFalse(model.canRetry)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isBuffering)
        XCTAssertEqual(model.player.rate, 0)
        XCTAssertTrue(model.player.currentItem === item)
        XCTAssertEqual(model.playbackError, originalError)
        XCTAssertEqual(progressReports, 1)
    }

    @MainActor
    func testStopWhileRetrySeekIsPendingNeverResumesPlayback() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("episode.wav")
        let model = EmbeddedPlayerModel()
        defer {
            model.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        await start(model, url: url, startAt: 8)
        try await waitUntil("The missing-file failure should be visible") {
            model.playbackError != nil
        }
        try writeSilentWAV(to: url)
        model.retry()
        let replacement = try XCTUnwrap(model.player.currentItem)
        model.stop()
        try await waitUntil("The replacement asset should load after stop") {
            replacement.status == .readyToPlay
        }
        await Task.yield()

        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isBuffering)
        XCTAssertFalse(model.canRetry)
        XCTAssertEqual(model.player.rate, 0)
    }

    @MainActor
    func testStopBeforeStartDoesNotInstallAnItem() async throws {
        let model = EmbeddedPlayerModel()
        model.stop()
        await start(model, url: FileManager.default.temporaryDirectory.appendingPathComponent("unused.wav"))

        XCTAssertNil(model.player.currentItem)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isBuffering)
        XCTAssertFalse(model.canRetry)
    }

    @MainActor
    private func start(
        _ model: EmbeddedPlayerModel,
        url: URL,
        startAt: TimeInterval? = nil,
        onFinished: @escaping () -> Void = {}
    ) async {
        await model.start(
            variants: [StreamVariant(url: url)],
            referer: nil,
            startAt: startAt,
            onProgress: { _ in },
            onFinished: onFinished
        )
    }

    @MainActor
    private func postFailure(for item: AVPlayerItem, message: String = "Test source failed") {
        let error = NSError(
            domain: "EmbeddedPlayerRecoveryTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: error]
        )
    }

    @MainActor
    private func waitForPlayback(
        _ model: EmbeddedPlayerModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await waitUntil("AVPlayer should become ready and actually play", file: file, line: line) {
            model.player.currentItem?.status == .readyToPlay
                && model.player.timeControlStatus == .playing
                && model.isPlaying && !model.isBuffering && model.playbackError == nil
        }
    }

    @MainActor
    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail(message, file: file, line: line)
                throw WaitError.timedOut(message)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private enum WaitError: Error {
        case timedOut(String)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddedPlayerRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A deterministic, playable fixture created on the simulator, with no
    /// network hosting or committed media binary involved.
    private func writeSilentWAV(to url: URL) throws {
        let sampleRate: UInt32 = 8_000
        let byteCount: UInt32 = 30 * sampleRate * 2
        var data = Data("RIFF".utf8)
        appendLittleEndian(UInt32(36) + byteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data) // PCM
        appendLittleEndian(UInt16(1), to: &data) // mono
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * 2, to: &data)
        appendLittleEndian(UInt16(2), to: &data) // bytes per sample
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(byteCount, to: &data)
        data.append(Data(count: Int(byteCount)))
        try data.write(to: url, options: .atomic)
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}
