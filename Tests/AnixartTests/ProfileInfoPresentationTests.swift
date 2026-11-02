import SwiftUI
import XCTest
@testable import Anixart

final class ProfileInfoPresentationTests: XCTestCase {
    func testCompactWidthUsesSheetWithoutRequiringAnAccessibilityFont() {
        XCTAssertEqual(ProfileInfoPresentationPolicy.kind(horizontal: .compact, vertical: .regular, dynamicType: .large), .sheet)
    }

    func testLandscapeAndUnknownTraitsPreferSheet() {
        XCTAssertEqual(ProfileInfoPresentationPolicy.kind(horizontal: .regular, vertical: .compact, dynamicType: .large), .sheet)
        XCTAssertEqual(ProfileInfoPresentationPolicy.kind(horizontal: nil, vertical: .regular, dynamicType: .large), .sheet)
        XCTAssertEqual(ProfileInfoPresentationPolicy.kind(horizontal: .regular, vertical: nil, dynamicType: .large), .sheet)
    }

    func testRegularSpaceKeepsAnchoredPopoverForNormalText() {
        for size in [DynamicTypeSize.large, .xLarge] {
            XCTAssertEqual(ProfileInfoPresentationPolicy.kind(horizontal: .regular, vertical: .regular, dynamicType: size), .popover)
        }
    }

    func testLargeDynamicTypeUsesSheetEvenInRegularSpace() {
        for size in [DynamicTypeSize.xxLarge, .xxxLarge, .accessibility1, .accessibility3, .accessibility5] {
            XCTAssertEqual(ProfileInfoPresentationPolicy.kind(horizontal: .regular, vertical: .regular, dynamicType: size), .sheet)
        }
    }

    func testLargeTextAndLandscapeUseTheLargeSheetDetent() {
        XCTAssertEqual(ProfileInfoPresentationPolicy.sheetDetents(vertical: .regular, dynamicType: .large), [.medium, .large])
        XCTAssertEqual(ProfileInfoPresentationPolicy.sheetDetents(vertical: .compact, dynamicType: .large), [.large])
        XCTAssertEqual(ProfileInfoPresentationPolicy.sheetDetents(vertical: .regular, dynamicType: .xxLarge), [.large])
    }

    @MainActor
    func testOnlyTheMatchingControlAndKindCanPresentTheItem() {
        let store = ProfileInfoPresentationStore()
        store.value = ProfileInfoPresentation(source: .contacts, kind: .sheet)
        let matching = profileInfoPresentationBinding(store.binding, source: .contacts, kind: .sheet)
        let otherControl = profileInfoPresentationBinding(store.binding, source: .reputation, kind: .sheet)
        let otherKind = profileInfoPresentationBinding(store.binding, source: .contacts, kind: .popover)
        XCTAssertEqual(matching.wrappedValue, store.value)
        XCTAssertNil(otherControl.wrappedValue)
        XCTAssertNil(otherKind.wrappedValue)
        otherControl.wrappedValue = nil
        otherKind.wrappedValue = nil
        XCTAssertNotNil(store.value)
    }

    @MainActor
    func testOlderPopoverDismissalCannotCloseTheNewSheet() {
        let store = ProfileInfoPresentationStore()
        store.value = ProfileInfoPresentation(source: .reputation, kind: .popover)
        let oldBinding = profileInfoPresentationBinding(store.binding, source: .reputation, kind: .popover)
        let replacement = ProfileInfoPresentation(source: .contacts, kind: .sheet)
        store.value = replacement
        XCTAssertNil(oldBinding.wrappedValue)
        oldBinding.wrappedValue = nil
        XCTAssertEqual(store.value, replacement)
    }

    @MainActor
    func testOlderDismissalCannotCloseAReopenedSameControl() {
        let store = ProfileInfoPresentationStore()
        let original = ProfileInfoPresentation(source: .reputation, kind: .popover)
        store.value = original
        let oldBinding = profileInfoPresentationBinding(store.binding, source: .reputation, kind: .popover)
        let reopened = ProfileInfoPresentation(source: .reputation, kind: .popover)
        store.value = reopened
        oldBinding.wrappedValue = nil
        dismissProfileInfoPresentation(store.binding, ifCurrent: original)
        XCTAssertEqual(store.value, reopened)
    }

    @MainActor
    func testCurrentBindingAndCloseButtonCanDismissTheirOwnPresentation() {
        let store = ProfileInfoPresentationStore()
        store.value = ProfileInfoPresentation(source: .contacts, kind: .sheet)
        let current = profileInfoPresentationBinding(store.binding, source: .contacts, kind: .sheet)
        current.wrappedValue = nil
        XCTAssertNil(store.value)
        let reopened = ProfileInfoPresentation(source: .reputation, kind: .popover)
        store.value = reopened
        dismissProfileInfoPresentation(store.binding, ifCurrent: reopened)
        XCTAssertNil(store.value)
    }

    @MainActor
    func testClearedAccountPresentationCannotBeRevivedByAnOldBinding() {
        let store = ProfileInfoPresentationStore()
        store.value = ProfileInfoPresentation(source: .contacts, kind: .sheet)
        let oldBinding = profileInfoPresentationBinding(store.binding, source: .contacts, kind: .sheet)
        store.value = nil
        XCTAssertNil(oldBinding.wrappedValue)
        oldBinding.wrappedValue = ProfileInfoPresentation(source: .contacts, kind: .sheet)
        XCTAssertNil(store.value)
    }
}

@MainActor
private final class ProfileInfoPresentationStore {
    var value: ProfileInfoPresentation?
    var binding: Binding<ProfileInfoPresentation?> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}
