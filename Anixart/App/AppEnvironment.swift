import Foundation
import SwiftUI
import AnixartKit

/// Single place the app is wired together, injected at the root with
/// `.environment(_:)` and read back with `@Environment(AppEnvironment.self)`.
@MainActor
@Observable
final class AppEnvironment {
    let client: AnixartClient
    let session: SessionController
    let tokenStore: any TokenStore

    init(tokenStore: any TokenStore = KeychainTokenStore()) {
        let client = AnixartClient(tokenStore: tokenStore)
        self.client = client
        self.tokenStore = tokenStore
        self.session = SessionController(client: client, tokenStore: tokenStore)
    }

    /// Environment for previews: no keychain, no signed-in user.
    static func preview() -> AppEnvironment {
        AppEnvironment(tokenStore: InMemoryTokenStore())
    }
}
