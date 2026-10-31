import Foundation

public enum ProfileSecurityEndpoints {
    public static func health() -> Endpoint<ProfileHealthStatusResponse> {
        Endpoint(path: "profile/health/status", auth: .required)
    }

    /// Unlike most lists, these two endpoints return a bare JSON array.
    public static func enforcements(account: Bool, page: Int) -> Endpoint<[ProfileEnforcement]> {
        Endpoint(path: "profile/health/enforcement/\(account ? "account" : "content")/all/\(page)", auth: .required)
    }

    public static func enforcement(id: Int) -> Endpoint<ProfileEnforcementResponse> {
        Endpoint(path: "profile/health/enforcement/\(id)", auth: .required)
    }

    /// ProfileEnforcementAppealResponse has no instance fields in the APK.
    public static func appeal(id: Int, message: String? = nil) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/health/enforcement/\(id)/appeal",
                 body: .json(ProfileEnforcementAppealRequest(message: message)), auth: .required)
    }

    public static func deletionStatus() -> Endpoint<ProfileDeletionResponse> {
        // The Android presenter treats NOT_FOUND (3) as the normal empty state.
        Endpoint(path: "profile/deletion/status", auth: .required, acceptedStatusCodes: [0, 3])
    }

    public static func requestDeletion(password: String) -> Endpoint<ProfileDeletionResponse> {
        Endpoint(method: .post, path: "profile/deletion/request", body: .form(["password": password]), auth: .required)
    }

    public static func cancelDeletion() -> Endpoint<ProfileDeletionResponse> {
        Endpoint(method: .post, path: "profile/deletion/cancel", auth: .required)
    }
}
