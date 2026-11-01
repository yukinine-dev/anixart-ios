import Foundation

public enum NotificationPreferenceEndpoints {
    public static func my() -> Endpoint<NotificationPreferencesResponse> {
        Endpoint(path: "profile/preference/notification/my", auth: .required)
    }

    /// These GETs toggle server state. They are mutations, with no boolean query
    /// parameter/body, and must only run after an explicit preference action.
    public static func toggle(_ flag: NotificationPreferenceFlag) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/preference/notification/\(flag.rawValue)/edit", auth: .required)
    }

    public static func editStatuses(_ ids: Set<Int>) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/notification/status/edit",
                 body: .json(NotificationStatusEditRequest(ids: ids)), auth: .required)
    }

    public static func editTypes(_ ids: Set<Int>) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/notification/type/edit",
                 body: .json(NotificationTypesEditRequest(ids: ids)), auth: .required)
    }

    public static func selectedReleases(page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(path: "profile/preference/notification/release/all/\(page)", auth: .required)
    }

    public static func releaseTypes(releaseID: Int) -> Endpoint<ReleaseNotificationPreferencesResponse> {
        Endpoint(path: "profile/preference/notification/release/type/\(releaseID)", auth: .required)
    }

    public static func editReleaseTypes(releaseID: Int, ids: Set<Int>) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/notification/release/type/edit",
                 body: .json(ReleaseNotificationTypesEditRequest(releaseID: releaseID, ids: ids)), auth: .required)
    }
}

extension NotificationEndpoints {
    public static func feed(_ filter: NotificationFeedFilter, page: Int) -> Endpoint<PageableResponse<AnixartNotification>> {
        Endpoint(path: "notification/\(filter.rawValue)/\(page)", auth: .required)
    }
}
