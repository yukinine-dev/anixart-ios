import Foundation

/// Server endpoints used by the Android client, version 10.5 (`com.swiftsoft.anixartd`).
///
/// The app ships a hardcoded fallback host and then asks `config/urls` for the live
/// list, so the host can move without a client update. `AnixartClient` follows the
/// same pattern: start on `defaultBaseURL`, then adopt whatever `config/urls` returns.
public enum AnixartEnvironment {
    /// Hardcoded fallback, from `StartPresenter` / `ConstantNetFetcher` in the APK.
    public static let defaultBaseURL = URL(string: "https://api-s.anixsekai.com/")!

    /// Host serving posters, screenshots and avatars.
    public static let staticHost = "static.anixart.tv"

    /// Web front end, used for deep links and legal pages.
    public static let webBaseURL = URL(string: "https://anixart-app.com/")!

    /// Hosts the Android app accepts in `anixart://` / https deep links.
    public static let deepLinkHosts = ["anixart.tv", "anixart.app", "anixartapp.com", "anixart-app.com"]

    /// `versionCode` the client reports to `config/toggles` and `config/urls`.
    ///
    /// Sent so the server can gate features and force updates. This is the value
    /// from the APK's own manifest -- `versionCode="26101718"` against
    /// `versionName="10.5"`.
    ///
    /// It was 1050 here for most of this port, which I had derived from the
    /// version *name*. The server gates on this field, so the client was
    /// announcing itself as years out of date on every launch, and anything the
    /// server withholds from an old client was being withheld. The Android app
    /// also appends it to the Kodik advert URL as `&v=`, which is where the
    /// mismatch became visible.
    public static let versionCode = 26_101_718

    /// Value sent in the `API-Version` header on the endpoints that require it.
    public static let apiVersion = "2"
}
