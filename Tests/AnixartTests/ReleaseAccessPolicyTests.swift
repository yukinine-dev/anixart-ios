import XCTest
import AnixartKit
@testable import Anixart

final class ReleaseAccessPolicyTests: XCTestCase {
    private func release(_ fields: String) throws -> Release {
        try JSONDecoder().decode(Release.self, from: Data("{\"id\":1,\(fields)}".utf8))
    }

    func testAdultRequiresExplicitAcknowledgement() throws {
        let adult = try release("\"age_rating\":5")
        XCTAssertTrue(ReleaseAccessPolicy.requiresAdultConfirmation(adult, acknowledged: false))
        XCTAssertFalse(ReleaseAccessPolicy.requiresAdultConfirmation(adult, acknowledged: true))
        XCTAssertFalse(ReleaseAccessPolicy.requiresAdultConfirmation(try release("\"age_rating\":4"), acknowledged: false))
        XCTAssertTrue(ReleaseAccessPolicy.requiresAdultConfirmation(try release("\"is_adult\":false,\"age_rating\":5"), acknowledged: false))
        XCTAssertFalse(ReleaseAccessPolicy.requiresAdultConfirmation(try release("\"is_adult\":true,\"age_rating\":4"), acknowledged: false))
        XCTAssertFalse(ReleaseAccessPolicy.requiresAdultConfirmation(try release("\"age_rating\":3"), acknowledged: false))
        XCTAssertFalse(ReleaseAccessPolicy.requiresAdultConfirmation(try release("\"is_adult\":false"), acknowledged: false))
    }

    func testLicensingDoesNotAllowPlayback() throws {
        let blocked = try release("\"is_ru_blocked\":true,\"note\":\"<b>Материал лицензирован</b>\"")
        XCTAssertTrue(ReleaseAccessPolicy.playbackMessage(blocked)?.contains("лицензирован") == true)
        XCTAssertEqual(ReleaseAccessPolicy.playbackMessage(try release("\"is_deleted\":true,\"is_ru_blocked\":true")), "Релиз удалён")
        XCTAssertNil(ReleaseAccessPolicy.playbackMessage(try release("\"is_ru_blocked\":false")))
        XCTAssertTrue(ReleaseAccessPolicy.playbackMessage(try release("\"is_view_blocked\":true"))?.contains("Недоступно в вашей стране") == true)
        XCTAssertFalse(ReleaseAccessPolicy.playbackMessage(try release("\"is_view_blocked\":true"))?.contains("лицензирован") == true)
        XCTAssertNotNil(ReleaseAccessPolicy.playbackMessage(try release("\"is_play_disabled\":true")))
    }

    @MainActor
    func testSignOutClearsAgeAcknowledgement() async {
        let defaults = UserDefaults.standard
        let key = ReleaseAccessPolicy.adultAcknowledgementKey
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)
        let rig = ProfileTestRig()
        await rig.session.signOut()
        XCTAssertFalse(defaults.bool(forKey: key))
    }

    func testOriginalWarningArtworkIsBundled() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sticker_4", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["w"] as? Int, 512)
        XCTAssertEqual(json["h"] as? Int, 512)
        XCTAssertEqual(json["fr"] as? Int, 60)
    }
}
