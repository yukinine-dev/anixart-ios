import AVFoundation
import Foundation
import AnixartKit

/// One downloaded or downloading episode, kept in a JSON index on the device.
struct EpisodeDownloadRecord: Codable, Identifiable, Equatable {
    enum State: String, Codable { case queued, downloading, finished, failed }

    var id: String
    var releaseID: Int
    var releaseTitle: String
    var posterURL: URL?
    var episodeNumber: Int
    var episodeName: String
    var state: State
    var progress: Double
    /// Path of the downloaded asset relative to the app's home directory (the container
    /// path changes between installs, so an absolute path would go stale).
    var relativePath: String?
    var message: String?
}

/// Offline episodes, as in the Android beta 3 «Загрузки»: episodes are fetched into the
/// app and play without a network.
///
/// How it differs from Android (measured from `EpisodeFileDownloader` in the beta 3 APK):
/// Android walks the HLS playlist itself and writes segments to a file. iOS hands the
/// stream URL to `AVAssetDownloadURLSession`, which does the same job natively and
/// survives the app being suspended. Only streams the player can already open are
/// downloadable (AniLibria today), because the link comes from `PlaybackResolver`.
@MainActor
@Observable
final class EpisodeDownloadCenter: NSObject, AVAssetDownloadDelegate {
    static let shared = EpisodeDownloadCenter()

    private(set) var records: [EpisodeDownloadRecord] = []
    private(set) var lastError: String?

    @ObservationIgnored private var session: AVAssetDownloadURLSession?
    @ObservationIgnored private var tasks: [String: AVAssetDownloadTask] = [:]
    @ObservationIgnored private var maxParallel = 2

    private static var indexURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("downloads-index.json")
    }

    private override init() {
        super.init()
        load()
    }

    // MARK: - Public

    /// Playable file for a finished record, nil while it is missing on disk.
    func fileURL(for record: EpisodeDownloadRecord) -> URL? {
        guard record.state == .finished, let path = record.relativePath else { return nil }
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func record(releaseID: Int, episodeNumber: Int) -> EpisodeDownloadRecord? {
        records.first { $0.id == Self.id(releaseID, episodeNumber) }
    }

    /// Queues episodes of one release. Episodes already queued or finished are skipped.
    func enqueue(release: Release, episodes: [Episode]) {
        lastError = nil
        for episode in episodes {
            guard let number = episode.position, number > 0 else { continue }
            let id = Self.id(release.id, number)
            if let existing = records.first(where: { $0.id == id }), existing.state != .failed { continue }
            records.removeAll { $0.id == id }
            records.append(EpisodeDownloadRecord(
                id: id, releaseID: release.id, releaseTitle: release.displayTitle, posterURL: release.posterURL,
                episodeNumber: number, episodeName: episode.displayName, state: .queued, progress: 0
            ))
            pendingEpisodes[id] = episode
        }
        save()
        startQueued()
    }

    func cancel(_ record: EpisodeDownloadRecord) {
        tasks[record.id]?.cancel()
        tasks[record.id] = nil
        pendingEpisodes[record.id] = nil
        remove(record)
        startQueued()
    }

    func delete(_ record: EpisodeDownloadRecord) {
        if let url = fileURL(for: record) { try? FileManager.default.removeItem(at: url) }
        cancel(record)
    }

    func deleteAll() {
        for record in records { delete(record) }
    }

    // MARK: - Queue

    @ObservationIgnored private var pendingEpisodes: [String: Episode] = [:]

    private var wifiOnly: Bool {
        UserDefaults.standard.object(forKey: DownloadPreferenceKey.wifiOnly) as? Bool ?? true
    }

    private func startQueued() {
        let running = records.filter { $0.state == .downloading }.count
        guard running < maxParallel else { return }
        let waiting = records.filter { $0.state == .queued && pendingEpisodes[$0.id] != nil }
        for record in waiting.prefix(maxParallel - running) { start(record) }
    }

    private func start(_ record: EpisodeDownloadRecord) {
        guard let episode = pendingEpisodes[record.id] else { return }
        update(record.id) { $0.state = .downloading }
        Task { [weak self] in
            let target = await PlaybackResolver.shared.target(for: episode)
            guard let self else { return }
            guard let variant = Self.pick(from: target.variants) else {
                self.fail(record.id, "Для этой серии нет прямой ссылки на видео. Скачать можно серии, которые открываются во встроенном плеере.")
                return
            }
            var headers: [String: String] = [:]
            if let referer = target.referer { headers["Referer"] = referer.absoluteString }
            let asset = AVURLAsset(url: variant.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let configuration = AVAssetDownloadConfiguration(asset: asset, title: "\(record.releaseTitle) · \(record.episodeName)")
            let session = self.ensureSession()
            let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
            task.taskDescription = record.id
            self.tasks[record.id] = task
            task.resume()
        }
    }

    /// Picks the quality chosen in Настройки → Загрузки: the tallest not above it, or the
    /// tallest available when none is set.
    private static func pick(from variants: [StreamVariant]) -> StreamVariant? {
        let wanted = UserDefaults.standard.integer(forKey: DownloadPreferenceKey.quality)
        let sorted = variants.sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        guard wanted > 0 else { return sorted.first }
        return sorted.first { ($0.height ?? 0) > 0 && ($0.height ?? 0) <= wanted } ?? sorted.last
    }

    private func ensureSession() -> AVAssetDownloadURLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: "app.anixart.client.episode-downloads")
        configuration.allowsCellularAccess = !wifiOnly
        configuration.sessionSendsLaunchEvents = true
        let created = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: .main)
        session = created
        return created
    }

    // MARK: - Records

    private static func id(_ releaseID: Int, _ episode: Int) -> String { "\(releaseID)-\(episode)" }

    private func update(_ id: String, _ change: (inout EpisodeDownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
    }

    private func remove(_ record: EpisodeDownloadRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    private func fail(_ id: String, _ message: String) {
        update(id) { $0.state = .failed; $0.message = message }
        pendingEpisodes[id] = nil
        tasks[id] = nil
        lastError = message
        save()
        startQueued()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              var stored = try? JSONDecoder().decode([EpisodeDownloadRecord].self, from: data) else { return }
        // Queued and running work does not survive a relaunch of this index; mark it so
        // the user can retry instead of watching a bar that will never move.
        for index in stored.indices where stored[index].state == .queued || stored[index].state == .downloading {
            stored[index].state = .failed
            stored[index].message = "Загрузка прервана. Запустите её заново."
        }
        records = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let url = Self.indexURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - AVAssetDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                                totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected.isFinite, expected > 0 else { return }
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        let fraction = min(1, max(0, loaded / expected))
        Task { @MainActor in self.update(id) { $0.progress = fraction } }
    }

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let home = NSHomeDirectory()
        let path = location.path.hasPrefix(home) ? String(location.path.dropFirst(home.count + 1)) : location.path
        Task { @MainActor in
            self.update(id) { $0.state = .finished; $0.progress = 1; $0.relativePath = path; $0.message = nil }
            self.pendingEpisodes[id] = nil
            self.tasks[id] = nil
            self.save()
            self.startQueued()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        let text = error.localizedDescription
        Task { @MainActor in self.fail(id, text) }
    }
}

enum DownloadPreferenceKey {
    /// Highest picture height to download; 0 takes the tallest available.
    static let quality = "downloads.quality"
    static let wifiOnly = "downloads.wifiOnly"
}
