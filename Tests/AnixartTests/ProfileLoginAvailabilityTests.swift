import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileLoginAvailabilityTests: XCTestCase {
    @MainActor
    func testBothExplicitAvailabilityAndLoadedRestrictionsAreRequired() throws {
        let info = ProfileResource<ChangeLoginInfoResponse>()
        let preferences = ProfileResource<ProfilePreferenceResponse>()
        info.adopt(try profileTestDecode(ChangeLoginInfoResponse.self, #"{"code":0,"is_change_available":true}"#))
        XCTAssertFalse(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
        for json in [#"{"code":0}"#, #"{"code":0,"is_change_login_banned":true}"#,
                     #"{"is_change_login_banned":false}"#] {
            preferences.adopt(try profileTestDecode(ProfilePreferenceResponse.self, json))
            XCTAssertFalse(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
        }
        preferences.adopt(try profileTestDecode(ProfilePreferenceResponse.self, #"{"code":0,"is_change_login_banned":false}"#))
        XCTAssertTrue(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
        for json in [#"{"code":0}"#, #"{"code":0,"is_change_available":false}"#,
                     #"{"is_change_available":true}"#] {
            info.adopt(try profileTestDecode(ChangeLoginInfoResponse.self, json))
            XCTAssertFalse(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
        }
    }

    @MainActor
    func testPendingOrFailedRestrictionRefreshCannotReuseThePreviouslyAllowedState() async throws {
        let info = ProfileResource<ChangeLoginInfoResponse>()
        let preferences = ProfileResource<ProfilePreferenceResponse>()
        info.adopt(try profileTestDecode(ChangeLoginInfoResponse.self, #"{"code":0,"is_change_available":true}"#))
        let allowed = try profileTestDecode(ProfilePreferenceResponse.self, #"{"code":0,"is_change_login_banned":false}"#)
        preferences.adopt(allowed)
        let gate = ProfileTestGate()
        defer { gate.release() }
        let refresh = Task { await preferences.load { await gate.wait(); throw URLError(.notConnectedToInternet) } }
        defer { refresh.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        XCTAssertFalse(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
        gate.release()
        await refresh.value
        XCTAssertEqual(preferences.value, allowed)
        XCTAssertNotNil(preferences.errorMessage)
        XCTAssertFalse(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
        preferences.adopt(allowed)
        XCTAssertTrue(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
    }

    @MainActor
    func testFailedAvailabilityRefreshAlsoBlocksSavingUntilRetry() async throws {
        let info = ProfileResource<ChangeLoginInfoResponse>()
        let preferences = ProfileResource<ProfilePreferenceResponse>()
        let allowed = try profileTestDecode(ChangeLoginInfoResponse.self, #"{"code":0,"is_change_available":true}"#)
        info.adopt(allowed)
        preferences.adopt(try profileTestDecode(ProfilePreferenceResponse.self, #"{"code":0,"is_change_login_banned":false}"#))
        await info.load { throw URLError(.notConnectedToInternet) }
        XCTAssertFalse(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
        info.adopt(allowed)
        XCTAssertTrue(ProfileLoginAvailability.mayChange(info: info, preferences: preferences))
    }
}
