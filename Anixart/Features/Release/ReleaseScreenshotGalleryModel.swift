import Foundation
import Observation
import UIKit

struct ReleaseScreenshotPresentation: Identifiable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
    let viewer: ProfileViewerKey
}

protocol GalleryImageLoading: Sendable {
    func image(for url: URL, pixelSize: CGFloat) async -> UIImage?
    func retryImage(for url: URL, pixelSize: CGFloat) async -> UIImage?
}

extension ImageLoader: GalleryImageLoading { }

/// Keeps the original order, including repeated URLs. Only the selected frame
/// and its two neighbours retain decoded images; the shared loader remains
/// bounded and supplies the existing disk cache, downsampling and mirror fallback.
@MainActor
@Observable
final class ReleaseScreenshotGalleryModel {
    enum Problem: Equatable {
        case invalidURL, loadFailed
        var message: String {
            self == .invalidURL ? "Ссылка на кадр недоступна" : "Не удалось загрузить кадр"
        }
    }
    enum PageState: Equatable {
        case loading, loaded, failed(Problem)
    }

    let urls: [URL]
    let viewer: ProfileViewerKey
    private(set) var selectedIndex: Int
    private(set) var images: [Int: UIImage] = [:]
    private(set) var pageStates: [Int: PageState] = [:]
    private(set) var isActive = false
    private(set) var isInvalidated = false
    private var pixelSize = 0
    private let session: SessionController
    @ObservationIgnored private let loader: any GalleryImageLoading
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    private var requestTokens: [Int: UUID] = [:]

    init(urls: [URL], initialIndex: Int, viewer: ProfileViewerKey, session: SessionController,
         loader: any GalleryImageLoading = ImageLoader.shared) {
        self.urls = urls
        self.viewer = viewer
        self.session = session
        self.loader = loader
        selectedIndex = urls.isEmpty ? 0 : min(max(0, initialIndex), urls.count - 1)
    }

    deinit { for task in tasks.values { task.cancel() } }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var positionText: String { "\(urls.isEmpty ? 0 : selectedIndex + 1) / \(urls.count)" }
    var canGoBack: Bool { isActive && !isInvalidated && hasCurrentViewer && selectedIndex > 0 }
    var canGoForward: Bool { isActive && !isInvalidated && hasCurrentViewer && selectedIndex + 1 < urls.count }
    var residentIndices: [Int] {
        guard isActive, !isInvalidated, !urls.isEmpty else { return [] }
        return Array(max(0, selectedIndex - 1)...min(urls.count - 1, selectedIndex + 1))
    }

    @discardableResult
    func select(_ index: Int) -> Bool {
        guard isActive, !isInvalidated, hasCurrentViewer, urls.indices.contains(index), index != selectedIndex else { return false }
        selectedIndex = index
        updateWindow()
        return true
    }

    func loadVisibleImages(pixelSize requestedSize: CGFloat) async {
        guard !isInvalidated, hasCurrentViewer, !Task.isCancelled else { return }
        let size = requestedSize.isFinite ? requestedSize : 1200
        let bounded = Int(min(2048, max(1, size)).rounded(.up))
        if pixelSize != bounded { clearImages(); pixelSize = bounded }
        isActive = true
        observeViewer()
        updateWindow()
        let pending = Array(tasks.values)
        for task in pending { await task.value }
    }

    func retry(_ index: Int) async {
        guard isActive, !isInvalidated, hasCurrentViewer, index == selectedIndex,
              pageStates[index] == .failed(.loadFailed) else { return }
        pageStates[index] = nil
        startLoading(index, retrying: true)
        await tasks[index]?.value
    }

    func suspend() {
        isActive = false
        clearImages()
    }

    func invalidate() {
        isInvalidated = true
        suspend()
    }

    private func updateWindow() {
        let residents = Set(residentIndices)
        for index in Array(tasks.keys) where !residents.contains(index) {
            tasks.removeValue(forKey: index)?.cancel()
            requestTokens[index] = nil
        }
        images = images.filter { residents.contains($0.key) }
        pageStates = pageStates.filter { residents.contains($0.key) }
        for index in residentIndices { startLoading(index) }
    }

    private func startLoading(_ index: Int, retrying: Bool = false) {
        guard pageStates[index] == nil, urls.indices.contains(index), isActive, !isInvalidated, hasCurrentViewer else { return }
        let url = urls[index]
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            pageStates[index] = .failed(.invalidURL)
            return
        }
        let key = ImageRequestKey(url: url, pixelSize: CGFloat(pixelSize), limit: 2048)
        let token = UUID()
        requestTokens[index] = token
        pageStates[index] = .loading
        tasks[index] = Task { [weak self, loader] in
            let image: UIImage?
            if retrying { image = await loader.retryImage(for: key.url, pixelSize: CGFloat(key.pixelSize)) }
            else { image = await loader.image(for: key.url, pixelSize: CGFloat(key.pixelSize)) }
            guard !Task.isCancelled else { return }
            self?.complete(image, index: index, token: token)
        }
    }

    private func complete(_ image: UIImage?, index: Int, token: UUID) {
        guard !isInvalidated, isActive, requestTokens[index] == token, residentIndices.contains(index) else { return }
        guard hasCurrentViewer else { invalidate(); return }
        requestTokens[index] = nil
        tasks[index] = nil
        if let image {
            // Duplicate URLs are distinct pages, but identical image resources.
            // A successful retry also repairs matching resident pages and retires
            // their older failed loads without changing the source array/index.
            for resident in residentIndices where urls[resident] == urls[index] {
                tasks.removeValue(forKey: resident)?.cancel()
                requestTokens[resident] = nil
                images[resident] = image
                pageStates[resident] = .loaded
            }
        } else {
            images[index] = nil
            pageStates[index] = .failed(.loadFailed)
        }
    }

    private func clearImages() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        requestTokens = [:]
        images = [:]
        pageStates = [:]
    }

    private func observeViewer() {
        withObservationTracking {
            _ = session.viewerKey
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, !self.hasCurrentViewer else { return }
                self.invalidate()
            }
        }
    }
}
