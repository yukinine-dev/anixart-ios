import SwiftUI
import UIKit
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileAvatarControlTests: XCTestCase {
    @MainActor
    func testOwnerAvatarHasOriginalMenuCommandsWithoutExecutingThem() throws {
        let profile = try profileTestDecode(Profile.self, #"{"id":42,"avatar":"https://example.invalid/avatar.png"}"#)
        var commands: [ProfileAvatarCommand] = []
        let control = ProfileAvatarControl(profile: profile, isOwnProfile: true) { commands.append($0) }
        XCTAssertEqual(control.menuCommands, [.open, .edit, .delete])
        XCTAssertEqual(control.menuCommands.map(\.title), ["Открыть", "Изменить", "Удалить"])
        XCTAssertTrue(commands.isEmpty)
    }

    @MainActor
    func testOwnerWithoutAvatarOnlyOffersEditing() throws {
        let profile = try profileTestDecode(Profile.self, #"{"id":42}"#)
        let control = ProfileAvatarControl(profile: profile, isOwnProfile: true) { _ in XCTFail("Construction must not dispatch a command") }
        XCTAssertEqual(control.menuCommands, [.edit])
    }

    @MainActor
    func testForeignAvatarNeverOffersOwnerCommands() throws {
        let profile = try profileTestDecode(Profile.self, #"{"id":71,"avatar":"https://example.invalid/avatar.png"}"#)
        let control = ProfileAvatarControl(profile: profile, isOwnProfile: false) { _ in XCTFail("Construction must not dispatch a command") }
        XCTAssertTrue(control.menuCommands.isEmpty)
    }

    @MainActor
    func testMenuSourceStaysPhotoSizedWithWideProposalsAndLargeText() throws {
        // No URL, device photo, permission prompt or live request is used.
        let profile = try profileTestDecode(Profile.self, #"{"id":42,"is_online":true}"#)
        var commandCount = 0
        for own in [true, false] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let control = ProfileAvatarControl(profile: profile, isOwnProfile: own) { _ in commandCount += 1 }
                    .dynamicTypeSize(textSize)
                let host = UIHostingController(rootView: control)
                let measured = host.sizeThatFits(in: CGSize(width: 1_024, height: 800))
                XCTAssertEqual(measured.width, ProfileAvatarControl.size, accuracy: 0.5)
                XCTAssertEqual(measured.height, ProfileAvatarControl.size, accuracy: 0.5)
            }
        }
        XCTAssertEqual(commandCount, 0)
    }
}
