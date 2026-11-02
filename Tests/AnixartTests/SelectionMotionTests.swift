import SwiftUI
import UIKit
import XCTest
@testable import Anixart

final class SelectionMotionTests: XCTestCase {
    private let normal = AppMotionPolicy(reduceMotion: false, resourceSaving: false)

    func testInitialAndProgrammaticSelectionsHaveNoMotionIntent() {
        let intent = SelectionMotionIntent<Int>()
        XCTAssertFalse(intent.hasPendingSelection)
        XCTAssertFalse(intent.shouldAnimate(nil))
        XCTAssertFalse(intent.shouldAnimate(1))
        XCTAssertNil(intent.animation(for: 1, policy: normal))
    }

    func testTouchOnlyAnimatesItsRequestedTarget() {
        var intent = SelectionMotionIntent<Int>()
        intent.register(20)
        XCTAssertTrue(intent.isPending(20))
        XCTAssertTrue(intent.shouldAnimate(20))
        XCTAssertFalse(intent.shouldAnimate(10))
        XCTAssertNotNil(intent.animation(for: 20, policy: normal))
        XCTAssertNil(intent.animation(for: 10, policy: normal))
    }

    func testRapidRetargetingAndOlderCompletionsKeepTheLatestIntent() {
        var intent = SelectionMotionIntent<Int>()
        intent.register(10)
        intent.register(20)
        intent.complete(10)
        intent.complete(nil)
        XCTAssertFalse(intent.isPending(10))
        XCTAssertTrue(intent.isPending(20))
        XCTAssertFalse(intent.shouldAnimate(10))
        XCTAssertTrue(intent.shouldAnimate(20))
    }

    func testKeyboardSelectionRemainsImmediateAndReplacesTouchIntent() {
        var intent = SelectionMotionIntent<Int>()
        intent.register(10)
        intent.register(20, fromKeyboard: true)
        XCTAssertTrue(intent.isPending(20))
        XCTAssertFalse(intent.shouldAnimate(10))
        XCTAssertFalse(intent.shouldAnimate(20))
        XCTAssertNil(intent.animation(for: 20, policy: normal))
    }

    func testCompletedIntentCannotReplayOnReturnOrProgrammaticChange() {
        var intent = SelectionMotionIntent<Int>()
        intent.register(20)
        intent.complete(20)
        XCTAssertFalse(intent.hasPendingSelection)
        XCTAssertFalse(intent.shouldAnimate(20))
        XCTAssertNil(intent.animation(for: 20, policy: normal))
    }

    func testResetRetiresAnUnfinishedSelection() {
        var intent = SelectionMotionIntent<Int>()
        intent.register(20)
        intent.reset()
        XCTAssertFalse(intent.hasPendingSelection)
        XCTAssertFalse(intent.isPending(20))
        XCTAssertFalse(intent.shouldAnimate(20))
    }

    func testAccessibilityAndResourceSavingSuppressTouchAnimation() {
        var intent = SelectionMotionIntent<Int>()
        intent.register(20)
        for policy in [AppMotionPolicy(reduceMotion: true, resourceSaving: false),
                       AppMotionPolicy(reduceMotion: false, resourceSaving: true)] {
            XCTAssertNil(intent.animation(for: 20, policy: policy))
        }
        XCTAssertNotNil(intent.animation(for: 20, policy: normal))
        XCTAssertEqual(normal.duration, 0.22)
    }

    func testExistingAnimationsCanKeepTheirOriginalTiming() {
        XCTAssertEqual(normal.resolvedAnimation(.default), Animation.default)
        let existing = Animation.easeOut(duration: 0.15)
        XCTAssertEqual(normal.resolvedAnimation(existing), existing)
        XCTAssertEqual(normal.resolvedAnimation(), normal.animation)
    }

    func testExistingAnimationOverridesCannotBypassReduceMotionOrResourceSaving() {
        for policy in [AppMotionPolicy(reduceMotion: true, resourceSaving: false),
                       AppMotionPolicy(reduceMotion: false, resourceSaving: true)] {
            XCTAssertNil(policy.resolvedAnimation(.default))
            XCTAssertNil(policy.resolvedAnimation(.easeOut(duration: 0.15)))
        }
    }

    func testKeyboardActivationSuppressesExistingAnimationOverrides() {
        XCTAssertNil(normal.resolvedAnimation(.default, animated: false))
        XCTAssertNil(normal.resolvedAnimation(animated: false))
    }

    @MainActor
    func testStateUpdatesStillCommitOnceWhenMotionIsDisabled() {
        for policy in [normal, AppMotionPolicy(reduceMotion: true, resourceSaving: false),
                       AppMotionPolicy(reduceMotion: false, resourceSaving: true)] {
            var updates = 0
            policy.perform(using: .default) { updates += 1 }
            XCTAssertEqual(updates, 1)
            policy.perform(animated: false, using: .default) { updates += 1 }
            XCTAssertEqual(updates, 2)
        }
    }

    @MainActor
    func testSelectionDoesNotShiftLabelSizeAcrossDynamicTypeAndTextStyles() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            for style in [Font.TextStyle.title3, .subheadline] {
                for title in ["Главная", "Оценки релизов"] {
                    let plain = measure(title: title, selected: false, style: style, size: size)
                    let selected = measure(title: title, selected: true, style: style, size: size)
                    XCTAssertEqual(plain.width, selected.width, accuracy: 0.5)
                    XCTAssertEqual(plain.height, selected.height, accuracy: 0.5)
                }
            }
        }
    }

    @MainActor
    func testCheckmarkHasReservedSpaceBeforeSelection() {
        for title in ["Все", "Озвучки", "Субтитры"] {
            let plain = measure(title: title, selected: false, checkmark: true)
            let selected = measure(title: title, selected: true, checkmark: true)
            let withoutMark = measure(title: title, selected: false)
            XCTAssertEqual(plain.width, selected.width, accuracy: 0.5)
            XCTAssertEqual(plain.height, selected.height, accuracy: 0.5)
            XCTAssertGreaterThan(plain.width, withoutMark.width)
        }
    }

    @MainActor
    func testProfileIconLabelHasStableSelectionSize() {
        let plain = measure(title: "Статистика", selected: false, style: .subheadline, icon: "chart.bar.fill")
        let selected = measure(title: "Статистика", selected: true, style: .subheadline, icon: "chart.bar.fill")
        XCTAssertEqual(plain.width, selected.width, accuracy: 0.5)
        XCTAssertEqual(plain.height, selected.height, accuracy: 0.5)
    }

    @MainActor
    func testSelectionLabelStillScalesWithDynamicType() {
        let normal = measure(title: "Озвучки", selected: true)
        let enlarged = measure(title: "Озвучки", selected: true, size: .accessibility3)
        XCTAssertGreaterThan(enlarged.width, normal.width)
        XCTAssertGreaterThan(enlarged.height, normal.height)
    }

    @MainActor
    private func measure(title: String, selected: Bool, style: Font.TextStyle = .title3,
                         size: DynamicTypeSize = .large, icon: String? = nil, checkmark: Bool = false) -> CGSize {
        let label = SelectionLabel(title: title, isSelected: selected, style: style,
                                   systemImage: icon, showsCheckmark: checkmark)
            .dynamicTypeSize(size)
            .fixedSize()
        let host = UIHostingController(rootView: label)
        return host.sizeThatFits(in: CGSize(width: 2_000, height: 2_000))
    }
}
