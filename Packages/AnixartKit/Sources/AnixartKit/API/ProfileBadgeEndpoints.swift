import Foundation

public enum ProfileBadgeEndpoints {
    public static func preview(code: String) -> Endpoint<BadgeClaimPreviewResponse> {
        Endpoint(path: "achievement/preview/\(code)", auth: .none)
    }

    public static func claim(code: String, badgeID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "achievement/get/\(code)", query: ["badge_id": String(badgeID)], auth: .required)
    }

    /// `recent` is an owner-only CSV of IDs; foreign reads send an empty string.
    public static func sections(profileID: Int, recent: String? = "") -> Endpoint<ProfileBadgeSectionsResponse> {
        Endpoint(path: "profile/\(profileID)/badge/list", query: ["recent": recent])
    }

    public static func all(profileID: Int, categoryID: Int, page: Int) -> Endpoint<PageableResponse<Badge>> {
        Endpoint(path: "profile/\(profileID)/badge/list/\(categoryID)/\(page)")
    }

    public static func select(id: Int) -> Endpoint<ProfileBadgeResponse> {
        Endpoint(path: "profile/preference/badge/edit/\(id)", auth: .required)
    }

    public static func remove() -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/preference/badge/remove", auth: .required)
    }

    // ProfileBadgeShowcaseResponse is status-only. Reload sections after success.
    public static func pin(id: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/badge/showcase/pin/\(id)", auth: .required)
    }

    public static func unpin(id: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/badge/showcase/unpin/\(id)", auth: .required)
    }

    public static func reorder(ids: [Int]) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/badge/showcase/reorder",
                 body: .json(BadgeReorderRequest(ids: ids)), auth: .required)
    }
}
