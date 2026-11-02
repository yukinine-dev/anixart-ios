import Foundation
import XCTest
@testable import Anixart

final class RecommendationHelpTests: XCTestCase {
    func testHelpIsExactOriginalAPKInformationDialogNotAnInventedEligibilityRule() {
        XCTAssertEqual(RecommendationHelp.title, "Информация")
        XCTAssertEqual(RecommendationHelp.dismissTitle, "Понятно")
        XCTAssertEqual(RecommendationHelp.message,
            "Рекомендации подбираются автоматически на основе выставленных вами оценок.\n\nДля подбора вы должны положительно оценить не менее 20 релизов, однако помните: чем честнее выставлены оценки, тем точнее будут подобраны рекомендации.\n\nОбновление происходит раз в сутки.")
    }

    @MainActor
    func testSuccessfulEmptyPersonalRecommendationsExposeReadOnlyHelp() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        for path in ["/discover/interesting", "/discover/discussing", "/discover/comments", "/discover/watching/0", "/discover/recommendations/0"] {
            rig.api.enqueue(path, json: #"{"code":0,"content":[]}"#)
        }
        let model = DiscoverViewModel(session: rig.session)
        await model.load()
        XCTAssertTrue(model.showsRecommendationExplanation)
        let count = rig.api.requests.count
        let profile = rig.session.profile
        _ = RecommendationHelp.message
        _ = RecommendationHelp.dismissTitle
        XCTAssertEqual(rig.api.requests.count, count)
        XCTAssertEqual(rig.session.profile, profile)
        XCTAssertTrue(rig.api.requests.filter { $0.url?.path.hasPrefix("/release/vote/") == true }.isEmpty)
    }

    @MainActor
    func testFailedRecommendationsAreNotMisrepresentedAsEmptyHelpState() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        for path in ["/discover/interesting", "/discover/discussing", "/discover/comments", "/discover/watching/0"] {
            rig.api.enqueue(path, json: #"{"code":0,"content":[]}"#)
        }
        rig.api.enqueue("/discover/recommendations/0", json: #"{"code":2}"#)
        let model = DiscoverViewModel(session: rig.session)
        await model.load()
        XCTAssertFalse(model.showsRecommendationExplanation)
        XCTAssertTrue(model.failedBlocks.contains("Рекомендации"))
    }
}
