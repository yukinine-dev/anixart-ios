import SwiftUI

struct RootHomeAction {
    let perform: @MainActor () -> Void
    @MainActor func callAsFunction() { perform() }
}

private struct RootHomeActionKey: EnvironmentKey {
    static let defaultValue: RootHomeAction? = nil
}

extension EnvironmentValues {
    var returnToHome: RootHomeAction? {
        get { self[RootHomeActionKey.self] }
        set { self[RootHomeActionKey.self] = newValue }
    }
}
