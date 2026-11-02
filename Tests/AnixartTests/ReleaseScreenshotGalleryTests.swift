import Foundation
import Observation
import UIKit
import XCTest
@testable import Anixart

final class ReleaseScreenshotGalleryTests: XCTestCase {
    private func urls(_ count: Int) -> [URL] {
        (0..<count).map { URL(string: "https://gallery-tests.invalid/\($0)")! }
    }

    @MainActor
    func testPresentationKeepsOriginalOrderDuplicatesAndTappedIndex() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = urls(2)
        let repeated = [source[0], source[0], source[1]]
        let presentation = ReleaseScreenshotPresentation(urls: repeated, initialIndex: 1, viewer: rig.session.viewerKey)
        let loader = GalleryTestLoader()
        let model = ReleaseScreenshotGalleryModel(urls: presentation.urls, initialIndex: presentation.initialIndex,
                                                 viewer: presentation.viewer, session: rig.session, loader: loader)
        XCTAssertEqual(model.urls, repeated)
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.positionText, "2 / 3")
        XCTAssertTrue(loader.requests.isEmpty, "No image work in init")
        await model.loadVisibleImages(pixelSize: 900)
        XCTAssertEqual(Set(model.images.keys), [0, 1, 2])
        XCTAssertEqual(model.urls, repeated)
    }

    @MainActor
    func testInitialIndexAndEmptyGalleryAreSafeWithoutImageRequests() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let loader = GalleryTestLoader()
        let empty = ReleaseScreenshotGalleryModel(urls: [], initialIndex: -90, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        await empty.loadVisibleImages(pixelSize: 1200)
        XCTAssertEqual(empty.positionText, "0 / 0")
        XCTAssertFalse(empty.canGoBack)
        XCTAssertFalse(empty.canGoForward)
        XCTAssertFalse(empty.select(0))
        XCTAssertTrue(loader.requests.isEmpty)
        let before = ReleaseScreenshotGalleryModel(urls: urls(3), initialIndex: -4, viewer: rig.session.viewerKey,
                                                  session: rig.session, loader: loader)
        let after = ReleaseScreenshotGalleryModel(urls: urls(3), initialIndex: 900, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        XCTAssertEqual(before.selectedIndex, 0)
        XCTAssertEqual(after.selectedIndex, 2)
    }

    @MainActor
    func testLargeGalleryOnlyLoadsAndRetainsThreeFramesAtBoundedDecodeSize() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = urls(100)
        let loader = GalleryTestLoader()
        let model = ReleaseScreenshotGalleryModel(urls: source, initialIndex: 50, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        await model.loadVisibleImages(pixelSize: .greatestFiniteMagnitude)
        XCTAssertEqual(model.residentIndices, [49, 50, 51])
        XCTAssertEqual(loader.requests.count, 3)
        XCTAssertTrue(loader.requests.allSatisfy { $0.pixelSize == 2048 })
        XCTAssertTrue(model.select(99))
        await model.loadVisibleImages(pixelSize: 2048)
        XCTAssertEqual(Set(model.images.keys), [98, 99])
        XCTAssertEqual(Set(model.pageStates.keys), [98, 99])
        XCTAssertEqual(loader.requests.count, 5)
        XCTAssertFalse(model.canGoForward)
        XCTAssertTrue(model.canGoBack)
        XCTAssertFalse(model.select(-1))
        XCTAssertFalse(model.select(100))
        XCTAssertEqual(model.positionText, "100 / 100")
    }

    @MainActor
    func testFailedCurrentImageRetriesOnlyThatFrameWithSameURL() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = urls(5)
        let loader = GalleryTestLoader()
        loader.enqueue(source[2], image: nil)
        let model = ReleaseScreenshotGalleryModel(urls: source, initialIndex: 2, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        await model.loadVisibleImages(pixelSize: 1000)
        XCTAssertEqual(model.pageStates[2], .failed(.loadFailed))
        XCTAssertNil(model.images[2])
        let retryImage = UIImage()
        loader.enqueue(source[2], image: retryImage)
        await model.retry(2)
        XCTAssertEqual(model.pageStates[2], .loaded)
        XCTAssertTrue(model.images[2] === retryImage)
        XCTAssertEqual(loader.requests.count, 4)
        XCTAssertEqual(loader.requests.last?.url, source[2])
        XCTAssertEqual(loader.retryRequests.count, 1)
        XCTAssertEqual(loader.retryRequests.first?.url, source[2])
        XCTAssertEqual(model.selectedIndex, 2)
    }

    @MainActor
    func testUnsafeAndRelativeURLsFailWithoutHandingThemToLoaderOrExternalSites() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = [URL(string: "/relative")!, URL(string: "file:///private/image")!,
                      URL(string: "https://user:secret@gallery-tests.invalid/image")!]
        let loader = GalleryTestLoader()
        let model = ReleaseScreenshotGalleryModel(urls: source, initialIndex: 1, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        await model.loadVisibleImages(pixelSize: 1000)
        XCTAssertEqual(model.pageStates.values.filter { $0 == .failed(.invalidURL) }.count, 3)
        XCTAssertTrue(loader.requests.isEmpty)
        await model.retry(1)
        XCTAssertTrue(loader.requests.isEmpty)
        XCTAssertEqual(model.urls, source)
    }

    @MainActor
    func testSceneSuspensionReleasesImagesAndRejectsLateLoadsThenResumesSameIndex() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = urls(5)
        let loader = GalleryTestLoader()
        let gate = ProfileTestGate()
        loader.enqueue(source[2], image: UIImage(), gate: gate)
        let model = ReleaseScreenshotGalleryModel(urls: source, initialIndex: 2, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        let loading = Task { await model.loadVisibleImages(pixelSize: 1000) }
        defer { gate.release(); loading.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        model.suspend()
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertTrue(model.pageStates.isEmpty)
        XCTAssertFalse(model.select(3))
        gate.release()
        await loading.value
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.selectedIndex, 2)
        await model.loadVisibleImages(pixelSize: 1000)
        XCTAssertEqual(Set(model.images.keys), [1, 2, 3])
        XCTAssertEqual(model.selectedIndex, 2)
    }

    @MainActor
    func testViewportReplacementRejectsAnOlderSmallDecodeAtSameIndex() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = urls(3)
        let loader = GalleryTestLoader()
        let gate = ProfileTestGate()
        let oldImage = UIImage()
        let currentImage = UIImage()
        loader.enqueue(source[1], image: oldImage, gate: gate)
        loader.enqueue(source[1], image: currentImage)
        let model = ReleaseScreenshotGalleryModel(urls: source, initialIndex: 1, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        let old = Task { await model.loadVisibleImages(pixelSize: 700) }
        defer { gate.release(); old.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        await model.loadVisibleImages(pixelSize: 1800)
        XCTAssertTrue(model.images[1] === currentImage)
        gate.release()
        await old.value
        XCTAssertTrue(model.images[1] === currentImage)
        XCTAssertEqual(loader.requests.filter { $0.url == source[1] }.map(\.pixelSize), [700, 1800])
    }

    @MainActor
    func testRetiredIndexCannotOverwriteANewerRevisitOfSameFrame() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = urls(6)
        let loader = GalleryTestLoader()
        let gate = ProfileTestGate()
        let currentImage = UIImage()
        loader.enqueue(source[1], image: UIImage(), gate: gate)
        loader.enqueue(source[1], image: currentImage)
        let model = ReleaseScreenshotGalleryModel(urls: source, initialIndex: 1, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        let old = Task { await model.loadVisibleImages(pixelSize: 1000) }
        defer { gate.release(); old.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        XCTAssertTrue(model.select(4))
        XCTAssertTrue(model.select(1))
        await model.loadVisibleImages(pixelSize: 1000)
        XCTAssertTrue(model.images[1] === currentImage)
        gate.release()
        await old.value
        XCTAssertTrue(model.images[1] === currentImage)
        XCTAssertEqual(Set(model.images.keys), [0, 1, 2])
    }

    @MainActor
    func testViewerChangeInvalidatesLoadedGalleryWithoutWaitingForViewAndCannotResume() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let loader = GalleryTestLoader()
        let model = ReleaseScreenshotGalleryModel(urls: urls(5), initialIndex: 2, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        await model.loadVisibleImages(pixelSize: 1000)
        let invalidated = XCTestExpectation(description: "Gallery retired on viewer change")
        withObservationTracking { _ = model.isInvalidated } onChange: { invalidated.fulfill() }
        try await rig.signIn()
        await fulfillment(of: [invalidated], timeout: 5)
        XCTAssertTrue(model.isInvalidated)
        XCTAssertFalse(model.isActive)
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertTrue(model.pageStates.isEmpty)
        let count = loader.requests.count
        await model.loadVisibleImages(pixelSize: 1800)
        await model.retry(2)
        XCTAssertFalse(model.select(3))
        XCTAssertEqual(loader.requests.count, count)
    }

    @MainActor
    func testCloseRejectsPendingImageAndNeverRestartsForSameViewer() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let source = urls(1)
        let loader = GalleryTestLoader()
        let gate = ProfileTestGate()
        loader.enqueue(source[0], image: UIImage(), gate: gate)
        let model = ReleaseScreenshotGalleryModel(urls: source, initialIndex: 0, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        let loading = Task { await model.loadVisibleImages(pixelSize: 1000) }
        defer { gate.release(); loading.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        model.invalidate()
        gate.release()
        await loading.value
        await model.loadVisibleImages(pixelSize: 2000)
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertTrue(model.isInvalidated)
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
    }

    @MainActor
    func testNonfiniteAndNegativeDecodeSizesAreBoundedAndDoNotRequestEntireArray() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let loader = GalleryTestLoader()
        let model = ReleaseScreenshotGalleryModel(urls: urls(10), initialIndex: 0, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        await model.loadVisibleImages(pixelSize: .nan)
        XCTAssertEqual(loader.requests.map(\.pixelSize), [1200, 1200])
        await model.loadVisibleImages(pixelSize: -1000)
        XCTAssertEqual(loader.requests.suffix(2).map(\.pixelSize), [1, 1])
        XCTAssertEqual(model.images.count, 2)
    }

    @MainActor
    func testRetryRepairsDuplicateResidentURLsWithoutCollapsingPagesOrIndex() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let url = urls(1)[0]
        let loader = GalleryTestLoader()
        for _ in 0..<3 { loader.enqueue(url, image: nil) }
        let model = ReleaseScreenshotGalleryModel(urls: [url, url, url], initialIndex: 1, viewer: rig.session.viewerKey,
                                                 session: rig.session, loader: loader)
        await model.loadVisibleImages(pixelSize: 1000)
        let image = UIImage()
        loader.enqueue(url, image: image)
        await model.retry(1)
        XCTAssertEqual(model.positionText, "2 / 3")
        XCTAssertEqual(model.urls.count, 3)
        XCTAssertEqual(model.pageStates.values.filter { $0 == .loaded }.count, 3)
        XCTAssertTrue(model.images.values.allSatisfy { $0 === image })
        XCTAssertEqual(loader.retryRequests.count, 1)
    }
}
