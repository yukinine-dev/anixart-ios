import Foundation

/// Bodies and methods verified against the installed Android APK, not inferred
/// from the endpoint names (several mutations are GETs).
public enum ProfilePreferenceEndpoints {
    public static func my() -> Endpoint<ProfilePreferenceResponse> {
        Endpoint(path: "profile/preference/my", auth: .required)
    }

    public static func social() -> Endpoint<ProfileSocialResponse> {
        Endpoint(path: "profile/preference/social", auth: .required)
    }

    public static func editSocial(_ pages: SocialPagesEditRequest) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/social/edit", body: .json(pages), auth: .required)
    }

    public static func editStatus(_ status: String) -> Endpoint<ProfilePreferenceResponse> {
        Endpoint(method: .post, path: "profile/preference/status/edit",
                 body: .json(ProfileStatusEditRequest(status: status)), auth: .required)
    }

    public enum PrivacyField: String, CaseIterable, Sendable {
        case statistics = "stats", counts, social, friendRequests
    }

    public static func editPrivacy(_ field: PrivacyField, permission: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/privacy/\(field.rawValue)/edit",
                 body: .json(PrivacyEditRequest(permission: permission)), auth: .required)
    }

    public static func pinSection(_ section: ProfileSection) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/section/edit",
                 body: .json(ProfileIDRequest(id: section.rawValue)), auth: .required)
    }

    /// Theme IDs, including any special IDs, come from `available_themes`.
    public static func selectTheme(id: Int) -> Endpoint<ProfileSelectThemeResponse> {
        Endpoint(method: .post, path: "profile/preference/themes/edit",
                 body: .json(ProfileIDRequest(id: id)), auth: .required)
    }

    public static func editAvatar(jpeg: Data) -> Endpoint<ProfilePreferenceResponse> {
        Endpoint(method: .post, path: "profile/preference/avatar/edit", body: .multipart(MultipartBody(parts: [
            .init(name: "image", filename: "avatar.jpg", contentType: "image/jpeg", data: jpeg),
            .init(name: "name", value: "")
        ])), auth: .required)
    }

    public static func deleteAvatar() -> Endpoint<ProfilePreferenceResponse> {
        Endpoint(path: "profile/preference/avatar/delete", auth: .required)
    }

    public static func loginInfo() -> Endpoint<ChangeLoginInfoResponse> {
        Endpoint(method: .post, path: "profile/preference/login/info", auth: .required)
    }

    public static func changeLogin(_ login: String) -> Endpoint<ChangeLoginResponse> {
        Endpoint(method: .post, path: "profile/preference/login/change", query: ["login": login], auth: .required)
    }

    public static func clearLoginHistory() -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/login/history/delete", auth: .required)
    }

    public static func changeEmail(currentEmail: String, currentPassword: String, newEmail: String) -> Endpoint<ChangeEmailResponse> {
        Endpoint(method: .post, path: "profile/preference/email/change", body: .form([
            "current_email": currentEmail, "current_password": currentPassword, "new_email": newEmail
        ]), auth: .required)
    }

    public static func resendEmail(currentEmail: String, currentPassword: String, newEmail: String, hash: String) -> Endpoint<ChangeEmailResendResponse> {
        Endpoint(method: .post, path: "profile/preference/email/resend", body: .form([
            "current_email": currentEmail, "current_password": currentPassword, "new_email": newEmail, "hash": hash
        ]), auth: .required)
    }

    /// The current APK's ChangeEmailVerifyResponse has no instance fields.
    public static func verifyEmail(newEmail: String, code: Int, hash: String) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/preference/email/verify",
                 query: ["new_email": newEmail, "code": String(code), "hash": hash], auth: .required)
    }

    public static func changePassword(current: String, new: String) -> Endpoint<ChangePasswordResponse> {
        Endpoint(method: .post, path: "profile/preference/password/change",
                 body: .form(["current": current, "new": new]), auth: .required)
    }

    public enum Service: String, CaseIterable, Sendable, Identifiable {
        case yandex, vk, telegram, google
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .yandex: return "Яндекс"
            case .vk: return "ВКонтакте"
            case .telegram: return "Telegram"
            case .google: return "Google"
            }
        }
    }

    public static func bind(_ service: Service, token: String) -> Endpoint<StatusResponse> {
        let key = (service == .google || service == .telegram) ? "idToken" : "accessToken"
        return Endpoint(method: .post, path: "profile/preference/\(service.rawValue)/bind",
                        body: .form([key: token]), auth: .required)
    }

    public static func unbind(_ service: Service) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "profile/preference/\(service.rawValue)/unbind", auth: .required)
    }
}
