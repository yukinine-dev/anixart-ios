import Foundation
import XCTest
@testable import AnixartKit

final class ProfileModelTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testProfilePreviewCommentsKeepCategoryAndEmbeddedParents() throws {
        let profile = try decode(Profile.self, #"""
        {"id":42,"comments_preview":[
            {"id":1,"release":71,"reply_count":2,"likes_count":3,"vote_count":4,"postedAtEpisode":6},
            {"id":2,"collection":{"id":72,"title":"Collection"}},
            {"id":3,"article":{"id":73,"payload":{"blocks":[]}}}
        ]}
        """#)
        let comments = try XCTUnwrap(profile.commentsPreview)
        XCTAssertEqual(comments.map(\.category), [.releases, .collections, .articles])
        XCTAssertEqual(comments.map { $0.location?.parentID }, [71, 72, 73])
        XCTAssertEqual(comments[0].replyCount, 2)
        XCTAssertEqual(comments[0].likesCount, 3)
        XCTAssertEqual(comments[0].voteCount, 4)
        XCTAssertEqual(comments[0].postedAtEpisode, 6)
        XCTAssertEqual(comments[1].collection?.value?.title, "Collection")
        XCTAssertEqual(comments[2].article?.value?.payload?.blocks, [])
    }

    func testCommentResponseKeysDifferFromComposerRequestKeys() throws {
        let comment = try decode(ProfileComment.self, #"""
        {"id":9,"parent_comment_id":2,"reply_count":4,"likes_count":6,"vote_count":7,
         "is_reply":true,"is_spoiler":true,"postedAtEpisode":12,"release":71}
        """#)
        XCTAssertEqual(comment.parentCommentId, 2)
        XCTAssertEqual(comment.threadRootID, 2)
        XCTAssertEqual(comment.replyCount, 4)
        XCTAssertEqual(comment.likesCount, 6)
        XCTAssertEqual(comment.voteCount, 7)
        XCTAssertEqual(comment.isReply, true)
        XCTAssertEqual(comment.isSpoiler, true)
        XCTAssertEqual(comment.postedAtEpisode, 12)
        let request = CommentAddRequest(message: "Reply", parentCommentId: comment.threadRootID, replyToProfileId: 42, spoiler: true)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(body["parentCommentId"] as? Int, 2)
        XCTAssertEqual(body["replyToProfileId"] as? Int, 42)
        XCTAssertEqual(body["spoiler"] as? Bool, true)
        XCTAssertNil(body["parent_comment_id"])
    }

    func testLegacyReleaseCommentBridgeRetainsThreadAndEpisodeContext() throws {
        let releaseComment = try decode(ReleaseComment.self, #"""
        {"id":9,"parent_comment_id":2,"profile":{"id":42,"login":"example"},"message":"reply",
         "timestamp":123,"reply_count":4,"likes_count":5,"vote_count":6,"vote":1,"is_reply":true,
         "is_spoiler":true,"postedAtEpisode":12,"release":71}
        """#)
        let comment = ProfileComment(releaseComment: releaseComment)
        XCTAssertEqual(comment.id, releaseComment.id)
        XCTAssertEqual(comment.profile, releaseComment.profile)
        XCTAssertEqual(comment.message, releaseComment.message)
        XCTAssertEqual(comment.timestamp, releaseComment.timestamp)
        XCTAssertEqual(comment.replyCount, releaseComment.replyCount)
        XCTAssertEqual(comment.likesCount, releaseComment.likesCount)
        XCTAssertEqual(comment.voteCount, releaseComment.voteCount)
        XCTAssertEqual(comment.vote, releaseComment.vote)
        XCTAssertEqual(comment.isReply, true)
        XCTAssertEqual(comment.isSpoiler, true)
        XCTAssertEqual(comment.postedAtEpisode, 12)
        XCTAssertEqual(comment.location, ProfileCommentLocation(category: .releases, parentID: 71))
        XCTAssertEqual(comment.threadRootID, 2)
    }

    func testInvalidOrSelfReferencingThreadRootFallsBackToCommentID() throws {
        for parent in [0, -1, 9] {
            let comment = try decode(ProfileComment.self, "{\"id\":9,\"parent_comment_id\":\(parent)}")
            XCTAssertEqual(comment.threadRootID, 9)
        }
        let sparse = try decode(ProfileComment.self, #"{"id":9}"#)
        XCTAssertEqual(sparse.threadRootID, 9)
        XCTAssertNil(sparse.location)
        let invalidParent = try decode(ProfileComment.self, #"{"id":9,"release":0}"#)
        XCTAssertNil(invalidParent.location)
    }

    func testProfileRatingNeverFallsBackToTheViewersVote() throws {
        let release = try decode(Release.self, #"{"id":71,"my_vote":2,"your_vote":5}"#)
        XCTAssertEqual(release.profileRating, 2)
        XCTAssertEqual(release.myVote, 2)
        XCTAssertEqual(release.yourVote, 5)
        let missing = try decode(Release.self, #"{"id":71,"your_vote":5}"#)
        XCTAssertNil(missing.profileRating)
        for value in [0, -1, 6] {
            let invalid = try decode(Release.self, "{\"id\":71,\"my_vote\":\(value),\"your_vote\":5}")
            XCTAssertNil(invalid.profileRating)
        }
    }

    func testDeletionFlagComesFromCodeNotDates() throws {
        XCTAssertEqual(try decode(ProfileDeletionResponse.self, #"{"code":0}"#).hasDeletionRequest, true)
        XCTAssertEqual(try decode(ProfileDeletionResponse.self, #"{"code":3,"requested_at":123,"delete_at":456}"#).hasDeletionRequest, false)
        XCTAssertNil(try decode(ProfileDeletionResponse.self, "{}").hasDeletionRequest)
        XCTAssertNil(try decode(ProfileDeletionResponse.self, #"{"code":2}"#).hasDeletionRequest)
    }

    func testArticleListsMediaAndFutureBlocksRoundTrip() throws {
        let payload = try decode(ArticlePayload.self, #"""
        {"block_count":3,"time":123,"version":"2","blocks":[
            {"id":"list","type":"list","data":{"style":"ordered","items":["one","two"],"item_count":2}},
            {"id":"media","type":"media","data":{"items":[{"id":"file","url":"https://example.invalid/image.jpg","width":100,"height":50}]}},
            {"id":"future","type":"future","data":{"nested":[true,null,{"value":3}],"text":"kept"}}
        ]}
        """#)
        XCTAssertEqual(payload.blockCount, 3)
        let blocks = try XCTUnwrap(payload.blocks)
        XCTAssertEqual(blocks[0].data?.items, .list(["one", "two"]))
        XCTAssertEqual(blocks[0].data?.itemCount, 2)
        guard case .media(let media)? = blocks[1].data?.items else { return XCTFail("Expected media objects") }
        XCTAssertEqual(media.first?.id, "file")
        XCTAssertEqual(media.first?.width, 100)
        XCTAssertEqual(media.first?.height, 50)
        XCTAssertNil(blocks[2].data)
        XCTAssertEqual(blocks[2].unsupportedData, .object([
            "nested": .array([.bool(true), .null, .object(["value": .number(3)])]), "text": .string("kept")
        ]))
        let roundTrip = try JSONDecoder().decode(ArticlePayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(roundTrip, payload)
    }

    func testRepostSupportsNestedObjectsIdentifiersAndNull() throws {
        let article = try decode(Article.self, #"""
        {"id":1,"contains_repost_article":true,"repost_article":{"id":2,"repost_article":3,"payload":{"blocks":[]}}}
        """#)
        XCTAssertEqual(article.repostArticle?.id, 2)
        XCTAssertEqual(article.repostArticle?.value?.repostArticle?.id, 3)
        XCTAssertNil(article.repostArticle?.value?.repostArticle?.value)
        XCTAssertEqual(try JSONDecoder().decode(Article.self, from: JSONEncoder().encode(article)), article)
        XCTAssertEqual(try decode(ArticleReference.self, "null"), .empty)
    }

    func testEnforcementDecodesCommentSubtypeExpiryChangesAndEnumForms() throws {
        let enforcement = try decode(ProfileEnforcement.self, #"""
        {"id":1,"type":"article_comment_edit","expiration_timestamp":123,"entity_id":9,
         "entity":{"id":9,"article":73,"message":"edited"},"appeal_type":"ADJUSTMENT","appeal_status":2,
         "changes":[{"type":"is_deleted","new_value":true},{"type":"is_spoiler","new_value":false},
                    {"type":"future","new_value":{"nested":1}}]}
        """#)
        XCTAssertEqual(enforcement.contentID, 9)
        XCTAssertEqual(enforcement.commentCategory, .articles)
        XCTAssertEqual(enforcement.appealType, .name("ADJUSTMENT"))
        XCTAssertEqual(enforcement.appealStatus, .ordinal(2))
        XCTAssertTrue(enforcement.isExpired(at: Date(timeIntervalSince1970: 123)))
        XCTAssertFalse(enforcement.isExpired(at: Date(timeIntervalSince1970: 122)))
        guard case .comment(let comment)? = enforcement.entity else { return XCTFail("Expected a typed comment") }
        XCTAssertEqual(comment.value?.location?.parentID, 73)
        XCTAssertEqual(enforcement.changes?.first, .deletion(true))
        XCTAssertEqual(enforcement.changes?[1], .spoiler(false))
        XCTAssertEqual(try JSONDecoder().decode(ProfileEnforcement.self, from: JSONEncoder().encode(enforcement)), enforcement)
    }

    func testSparseAndFutureEnforcementEntitiesAreNotDiscarded() throws {
        let sparse = try decode(ProfileEnforcement.self, #"{"id":1,"type":"collection_edit","entity":72}"#)
        XCTAssertEqual(sparse.contentID, 72)
        let future = try decode(ProfileEnforcement.self, #"{"id":2,"type":"future","entity":{"custom":[1,true]}}"#)
        XCTAssertEqual(future.entity, .unknown(.object(["custom": .array([.number(1), .bool(true)])])))
        let unsupportedKnown = try decode(ProfileEnforcement.self, #"{"id":3,"type":"article_edit","entity":{"future":"value"}}"#)
        XCTAssertEqual(unsupportedKnown.entity, .unknown(.object(["future": .string("value")])))
        XCTAssertEqual(try JSONDecoder().decode(ProfileEnforcement.self, from: JSONEncoder().encode(future)), future)
    }

    func testPreferencesKeepServerThemeChoicesAndServiceFlags() throws {
        let preferences = try decode(ProfilePreferenceResponse.self, #"""
        {"code":0,"available_themes":[{"id":-7,"name":"Special"},{"id":123,"name":"New"}],
         "pinned_section_id":5,"selected_theme_id":123,"privacy_stats":2,"privacy_counts":1,
         "privacy_friend_requests":1,"privacy_social":0,"is_vk_bound":true,"is_google_bound":false}
        """#)
        XCTAssertEqual(preferences.availableThemes?.map(\.id), [-7, 123])
        XCTAssertEqual(preferences.pinnedSectionId, ProfileSection.badges.rawValue)
        XCTAssertEqual(preferences.selectedThemeId, 123)
        XCTAssertEqual(preferences.privacyStats, 2)
        XCTAssertEqual(preferences.privacyFriendRequests, 1)
        XCTAssertEqual(preferences.isBound(to: .vk), true)
        XCTAssertEqual(preferences.isBound(to: .google), false)
        XCTAssertNil(preferences.isBound(to: .yandex))
    }

    func testShowcaseThemeProjectsEveryFlatProfileSettingWithoutChangingWireShape() throws {
        let settings = """
        "theme_enabled":true,"theme_animation_enabled":false,"theme_animation_speed":"ultra",
        "theme_background_alpha":0.25,"theme_background_mode":"tile","theme_background_url":"https://example.invalid/bg.gif",
        "theme_gradient_angle":"diagonal_tr_bl","theme_gradient_start_color":"#80402010","theme_gradient_end_color":"#112233",
        "theme_icon_alpha":0.75,"theme_icon_color":"red","theme_icon_density":"high","theme_icon_res_name":"ic_heart",
        "theme_icon_size":"large","theme_icon_url":"https://example.invalid/icon.gif"
        """
        let profile = try decode(Profile.self,
            "{\"id\":42,\"login\":\"Owner\",\(settings),\"theme\":{\"id\":999,\"theme_enabled\":false}}")
        let expected = try decode(ProfileTheme.self, "{\"id\":42,\(settings)}")
        XCTAssertEqual(profile.showcaseTheme, expected)
        XCTAssertNil(profile.showcaseTheme.name)
        let encoded = try JSONEncoder().encode(profile)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(body["theme"])
        XCTAssertNil(body["showcaseTheme"])
        XCTAssertNil(body["selected_theme_id"])
        XCTAssertEqual(body["theme_icon_res_name"] as? String, "ic_heart")
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: encoded), profile)
    }

    func testShowcaseThemePreservesMissingDisabledAndFutureSettings() throws {
        let sparse = try decode(Profile.self, #"{"id":42}"#)
        XCTAssertEqual(sparse.showcaseTheme, try decode(ProfileTheme.self, #"{"id":42}"#))
        for enabled in [false, true] {
            let settings = "\"theme_enabled\":\(enabled),\"theme_animation_enabled\":null,"
                + "\"theme_icon_alpha\":0,\"theme_icon_density\":\"future_density\","
                + "\"theme_background_mode\":\"future_mode\",\"theme_icon_res_name\":\"ic_future\""
            let profile = try decode(Profile.self, "{\"id\":42,\(settings)}")
            XCTAssertEqual(profile.showcaseTheme, try decode(ProfileTheme.self, "{\"id\":42,\(settings)}"))
        }
    }

    func testShowcaseThemeIdentityIgnoresUnrelatedProfileChanges() throws {
        var profile = try decode(Profile.self, #"{"id":42,"theme_enabled":true,"theme_icon_res_name":"ic_heart"}"#)
        let theme = profile.showcaseTheme
        profile.login = "Renamed"
        profile.ratingScore = 100
        profile.pinnedSectionId = ProfileSection.comments.rawValue
        XCTAssertEqual(profile.showcaseTheme, theme)
        profile.id = 43
        XCTAssertEqual(profile.showcaseTheme.id, 43)
        XCTAssertNotEqual(profile.showcaseTheme, theme)
    }

    func testStatusAndNicknameLimitsCountUTF16WithoutSplittingGraphemes() {
        XCTAssertTrue(ProfileEditorRules.isValidStatus(String(repeating: "🙂", count: 40)))
        XCTAssertFalse(ProfileEditorRules.isValidStatus(String(repeating: "🙂", count: 41)))
        XCTAssertTrue(ProfileEditorRules.isValidLoginLength("a🙂"))
        XCTAssertFalse(ProfileEditorRules.isValidLoginLength("🙂"))
        XCTAssertTrue(ProfileEditorRules.isValidLoginLength(String(repeating: "🙂", count: 10)))
        XCTAssertFalse(ProfileEditorRules.isValidLoginLength(String(repeating: "🙂", count: 11)))
        let prefix = String(repeating: "a", count: 79)
        XCTAssertEqual(ProfileEditorRules.limitedStatus(prefix + "🙂"), prefix)
        XCTAssertEqual(ProfileEditorRules.limitedStatus(prefix + "e\u{301}"), prefix)
        XCTAssertEqual(ProfileEditorRules.limitedStatus(String(repeating: "a", count: 78) + "e\u{301}" + "x"),
                       String(repeating: "a", count: 78) + "e\u{301}")
    }

    func testEmailCodeRequiresASCIIAndFitsJavaInt() {
        XCTAssertEqual(ProfileEditorRules.emailVerificationCode(" 000123\n"), 123)
        XCTAssertEqual(ProfileEditorRules.emailVerificationCode("2147483647"), Int(Int32.max))
        for value in ["", " ", "2147483648", "999999999999999999999", "-1", "+1", "１２３", "١٢٣", "1 2", "1.0"] {
            XCTAssertNil(ProfileEditorRules.emailVerificationCode(value), value)
        }
    }

    func testRecentBadgesArePositiveUniqueAndLimitedToFour() {
        XCTAssertEqual(ProfileEditorRules.recentBadgeIDs(adding: 3, to: [1, 3, 0, -1, 2, 4, 5]), [3, 1, 2, 4])
        XCTAssertEqual(ProfileEditorRules.recentBadgeIDs(adding: 0, to: [1, 1, 2]), [1, 2])
        XCTAssertEqual(ProfileEditorRules.showcaseLimit, 3)
        XCTAssertEqual(ProfileEditorRules.minimumCoverReputation, 3)
        XCTAssertEqual(ProfileSection.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5])
    }
}
