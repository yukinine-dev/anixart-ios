import Foundation

/// `auth/*`. Every call is form-encoded and unauthenticated.
///
/// Sign-up is a two-step flow in the Android client: `signUp` returns a `hash`,
/// the user receives a code by email, and `verify` exchanges hash + code for a
/// token. `X-Long-Code: 1` asks the server for the longer code format.
public enum AuthEndpoints {
    public static func signIn(login: String, password: String) -> Endpoint<SignInResponse> {
        Endpoint(
            method: .post,
            path: "auth/signIn",
            body: .form(["login": login, "password": password]),
            auth: .none
        )
    }

    public static func signUp(login: String, email: String, password: String) -> Endpoint<SignUpResponse> {
        Endpoint(
            method: .post,
            path: "auth/signUp",
            body: .form(["login": login, "email": email, "password": password]),
            auth: .none,
            headers: ["X-Long-Code": "1"]
        )
    }

    /// Completes sign-up (or a social sign-up) with the emailed code.
    ///
    /// Pass back exactly the credentials used to start the flow plus the `hash`
    /// the server returned; the Android client sends the unused fields as empty.
    public static func verify(
        login: String,
        email: String,
        password: String = "",
        vkAccessToken: String = "",
        googleIdToken: String = "",
        telegramIdToken: String = "",
        yandexAccessToken: String = "",
        hash: String,
        code: String
    ) -> Endpoint<VerifyResponse> {
        Endpoint(
            method: .post,
            path: "auth/verify",
            body: .form([
                "login": login,
                "email": email,
                "password": password,
                "vkAccessToken": vkAccessToken,
                "googleIdToken": googleIdToken,
                "telegramIdToken": telegramIdToken,
                "yandexAccessToken": yandexAccessToken,
                "hash": hash,
                "code": code
            ]),
            auth: .none
        )
    }

    public static func checkLogin(_ login: String) -> Endpoint<StatusResponse> {
        Endpoint(
            method: .post,
            path: "auth/checkLogin",
            body: .form(["login": login]),
            auth: .none
        )
    }

    /// Starts password recovery; `data` is the login or email.
    public static func restore(data: String) -> Endpoint<RestoreResponse> {
        Endpoint(
            method: .post,
            path: "auth/restore",
            body: .form(["data": data]),
            auth: .none,
            headers: ["X-Long-Code": "1"]
        )
    }

    public static func restoreVerify(
        data: String,
        password: String,
        hash: String,
        code: String
    ) -> Endpoint<RestoreVerifyResponse> {
        Endpoint(
            method: .post,
            path: "auth/restore/verify",
            body: .form(["data": data, "password": password, "hash": hash, "code": code]),
            auth: .none
        )
    }

    // MARK: - Social sign-in
    //
    // Each provider has one path used for both sign-in and sign-up: posting only the
    // provider token signs in, while adding `login` + `email` registers a new account.

    public static func signInWithVK(accessToken: String) -> Endpoint<VkResponse> {
        Endpoint(method: .post, path: "auth/vk", body: .form(["vkAccessToken": accessToken]), auth: .none)
    }

    public static func signInWithGoogle(idToken: String) -> Endpoint<GoogleResponse> {
        Endpoint(method: .post, path: "auth/google", body: .form(["googleIdToken": idToken]), auth: .none)
    }

    public static func signInWithTelegram(idToken: String) -> Endpoint<TelegramResponse> {
        Endpoint(method: .post, path: "auth/telegram", body: .form(["telegramIdToken": idToken]), auth: .none)
    }

    public static func signInWithYandex(accessToken: String) -> Endpoint<YandexResponse> {
        Endpoint(method: .post, path: "auth/yandex", body: .form(["yandexAccessToken": accessToken]), auth: .none)
    }

    /// Registers the FCM/APNs token for push notifications.
    public static func registerPushToken(_ token: String) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "auth/firebase", query: ["token": token], auth: .required)
    }
}
