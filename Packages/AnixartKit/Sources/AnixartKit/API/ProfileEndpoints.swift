import Foundation

/// `profile/*`.
public enum ProfileEndpoints {
    public static func profile(id: Int) -> Endpoint<ProfileResponse> {
        Endpoint(path: "profile/\(id)")
    }

    /// Flags for the signed-in account (privilege level, ban state, sponsorship).
    public static func myInfo() -> Endpoint<ProfileInfoResponse> {
        Endpoint(path: "profile/info", auth: .required)
    }

    public static func social(id: Int) -> Endpoint<ProfileSocialResponse> {
        Endpoint(path: "profile/social/\(id)")
    }

    public static func friends(of profileID: Int, page: Int) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(path: "profile/friend/all/\(profileID)/\(page)")
    }

    public static func incomingFriendRequests(page: Int) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(path: "profile/friend/requests/in/\(page)", auth: .required)
    }

    public static func outgoingFriendRequests(page: Int) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(path: "profile/friend/requests/out/\(page)", auth: .required)
    }

    public static func sendFriendRequest(to profileID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/friend/request/send/\(profileID)", auth: .required)
    }

    public static func removeFriend(_ profileID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/friend/request/remove/\(profileID)", auth: .required)
    }

    /// Releases this profile has rated.
    public static func ratedReleases(profileID: Int, page: Int, sort: Int? = nil) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            path: "profile/vote/release/voted/\(profileID)/\(page)",
            query: ["sort": sort.map { String($0) }]
        )
    }

    /// Releases in the user's lists that they have not rated yet.
    public static func unratedReleases(page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(path: "profile/vote/release/unvoted/\(page)", auth: .required)
    }

    public static func blockList(page: Int) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(path: "profile/blocklist/all/\(page)", auth: .required)
    }

    public static func block(profileID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/blocklist/add/\(profileID)", auth: .required)
    }

    public static func unblock(profileID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/blocklist/remove/\(profileID)", auth: .required)
    }
}

/// `notification/*`.
public enum NotificationEndpoints {
    /// The mixed feed. Entries are polymorphic -- see `AnixartNotification`.
    public static func all(page: Int) -> Endpoint<PageableResponse<AnixartNotification>> {
        Endpoint(path: "notification/all/\(page)", auth: .required)
    }

    public static func episodes(page: Int) -> Endpoint<PageableResponse<AnixartNotification>> {
        Endpoint(path: "notification/episodes/\(page)", auth: .required)
    }

    public static func friends(page: Int) -> Endpoint<PageableResponse<AnixartNotification>> {
        Endpoint(path: "notification/friends/\(page)", auth: .required)
    }

    public static func unreadCount() -> Endpoint<NotificationCountResponse> {
        Endpoint(path: "notification/count", auth: .required)
    }

    public static func markAllRead() -> Endpoint<StatusResponse> {
        Endpoint(path: "notification/read", auth: .required)
    }

    public static func deleteAll() -> Endpoint<StatusResponse> {
        Endpoint(path: "notification/delete/all", auth: .required)
    }
}

/// `config/*` -- served before anything else so the client can pick up host moves,
/// feature flags and a forced-update notice.
public enum ConfigEndpoints {
    public static func urls(isBeta: Bool = false) -> Endpoint<ConfigUrlsResponse> {
        Endpoint(
            path: "config/urls",
            query: [
                "version_code": String(AnixartEnvironment.versionCode),
                "is_beta": String(isBeta)
            ],
            auth: .optional
        )
    }

    public static func toggles(isBeta: Bool = false, useMirrors: Bool = false) -> Endpoint<TogglesResponse> {
        Endpoint(
            path: "config/toggles",
            query: [
                "version_code": String(AnixartEnvironment.versionCode),
                "is_beta": String(isBeta),
                "is_api_alt": String(useMirrors)
            ],
            auth: .optional
        )
    }
}
