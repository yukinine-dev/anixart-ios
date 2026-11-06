import CoreGraphics
import XCTest
@testable import Anixart

final class EnhancedFrameRenderStateTests: XCTestCase {
    func testNoDecodedFrameDoesNotRequestRendering() {
        let state = EnhancedFrameRenderState()
        XCTAssertFalse(state.needsRender(configuration: configuration()))
    }

    func testOneSubmittedFrameSkipsUnchangedDisplayTicks() {
        var state = EnhancedFrameRenderState()
        let config = configuration()
        state.receivedFrame()
        XCTAssertTrue(state.needsRender(configuration: config))
        state.didSubmit(configuration: config)

        for _ in 0..<120 {
            XCTAssertFalse(state.needsRender(configuration: config))
        }
    }

    func testNextDecodedFrameRendersAtTheSameConfiguration() {
        var state = submittedState()
        state.receivedFrame()
        XCTAssertTrue(state.needsRender(configuration: configuration()))
        state.didSubmit(configuration: configuration())
        XCTAssertFalse(state.needsRender(configuration: configuration()))
    }

    func testFrameRemainsPendingIfSubmissionCannotHappen() {
        var state = submittedState()
        state.receivedFrame()
        // The renderer cannot obtain a drawable/command buffer, so it never
        // calls didSubmit. The pending frame must survive until a later tick.
        for _ in 0..<3 {
            XCTAssertTrue(state.needsRender(configuration: configuration()))
        }
        state.didSubmit(configuration: configuration())
        XCTAssertFalse(state.needsRender(configuration: configuration()))
    }

    func testLatestFrameCanReplaceAnUnsubmittedFrame() {
        var state = EnhancedFrameRenderState()
        state.receivedFrame()
        state.receivedFrame()
        XCTAssertTrue(state.needsRender(configuration: configuration()))
        state.didSubmit(configuration: configuration())
        XCTAssertFalse(state.needsRender(configuration: configuration()))
    }

    func testPausedFrameRedrawsOnceForResize() {
        assertConfigurationChange(configuration(size: CGSize(width: 1280, height: 720)))
    }

    func testPausedFrameRedrawsOnceForFitFillChange() {
        assertConfigurationChange(configuration(isFilling: true))
    }

    func testPausedFrameRedrawsOnceForEveryEnhancementMode() {
        for strength in VideoEnhanceFilter.Strength.allCases where strength != .medium {
            assertConfigurationChange(configuration(strength: strength))
        }
    }

    func testInvalidationRePresentsPausedFrameEvenAtSameSize() {
        var state = submittedState()
        state.invalidatePresentation()
        XCTAssertTrue(state.needsRender(configuration: configuration()))
        state.didSubmit(configuration: configuration())
        XCTAssertFalse(state.needsRender(configuration: configuration()))
    }

    func testInvalidationBeforeFirstFrameDoesNotInventAFrame() {
        var state = EnhancedFrameRenderState()
        state.invalidatePresentation()
        XCTAssertFalse(state.needsRender(configuration: configuration()))
    }

    func testItemResetNeedsANewFrameEvenWithTheSameConfiguration() {
        var state = submittedState()
        state.reset()
        XCTAssertFalse(state.needsRender(configuration: configuration()))
        state.receivedFrame()
        XCTAssertTrue(state.needsRender(configuration: configuration()))
    }

    func testInvalidDrawableSizesDoNotConsumePendingFrame() {
        let invalidSizes = [
            CGSize.zero,
            CGSize(width: 1920, height: 0),
            CGSize(width: -1, height: 1080),
            CGSize(width: CGFloat.infinity, height: 1080),
            CGSize(width: 1920, height: CGFloat.nan)
        ]
        for size in invalidSizes {
            var state = EnhancedFrameRenderState()
            state.receivedFrame()
            let invalid = configuration(size: size)
            XCTAssertFalse(state.needsRender(configuration: invalid))
            state.didSubmit(configuration: invalid)
            XCTAssertTrue(state.needsRender(configuration: configuration()))
        }
    }

    private func submittedState() -> EnhancedFrameRenderState {
        var state = EnhancedFrameRenderState()
        state.receivedFrame()
        state.didSubmit(configuration: configuration())
        return state
    }

    private func assertConfigurationChange(
        _ changed: EnhancedFrameRenderState.Configuration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var state = submittedState()
        XCTAssertTrue(state.needsRender(configuration: changed), file: file, line: line)
        state.didSubmit(configuration: changed)
        XCTAssertFalse(state.needsRender(configuration: changed), file: file, line: line)
        XCTAssertTrue(state.needsRender(configuration: configuration()), file: file, line: line)
    }

    private func configuration(
        size: CGSize = CGSize(width: 1920, height: 1080),
        isFilling: Bool = false,
        strength: VideoEnhanceFilter.Strength = .medium
    ) -> EnhancedFrameRenderState.Configuration {
        .init(drawableSize: size, isFilling: isFilling, strength: strength)
    }
}
