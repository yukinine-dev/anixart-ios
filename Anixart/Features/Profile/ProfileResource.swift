import Foundation
import SwiftUI
import AnixartKit

/// Shared state for the profile's single-response screens. A cancelled page load
/// isn't an error, and an older request cannot overwrite a later refresh.
@MainActor
@Observable
final class ProfileResource<Value: Decodable & Sendable> {
    private(set) var value: Value?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasAttemptedLoad = false
    private var generation = 0

    func reset() {
        generation += 1
        value = nil
        isLoading = false
        hasAttemptedLoad = false
        errorMessage = nil
    }

    /// A successful edit supersedes any load that started before it.
    func adopt(_ updated: Value) {
        generation += 1
        value = updated
        isLoading = false
        hasAttemptedLoad = true
        errorMessage = nil
    }

    @discardableResult
    func load(_ endpoint: Endpoint<Value>, using client: AnixartClient) async -> Value? {
        await load { try await client.send(endpoint) }
    }

    @discardableResult
    func load(_ fetch: () async throws -> Value) async -> Value? {
        generation += 1
        let token = generation
        isLoading = true
        hasAttemptedLoad = true
        errorMessage = nil
        defer { if token == generation { isLoading = false } }
        do {
            let response = try await fetch()
            try Task.checkCancellation()
            guard token == generation else { return nil }
            value = response
            return response
        } catch {
            if token == generation, !ProfileRequestFailure.isCancellation(error) {
                errorMessage = Paginator<Release>.message(for: error)
            }
            return nil
        }
    }
}

enum ProfileRequestFailure {
    static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

@MainActor
struct ProfileResourceState<Value: Decodable & Sendable>: View {
    let resource: ProfileResource<Value>
    let title: String
    var retry: (() async -> Void)?

    var body: some View {
        if resource.isLoading || !resource.hasAttemptedLoad {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if let message = resource.errorMessage {
            StatusMessageView(title: title, message: message, systemImage: "wifi.exclamationmark", retry: retry)
        } else if resource.value == nil {
            StatusMessageView(title: "Данные недоступны", message: "Сервер не вернул данные для этого экрана.", retry: retry)
        }
    }
}

@MainActor
struct ProfileAccountNotice: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey?

    var body: some View {
        if account == nil || env.session.accountKey != account {
            Section {
                Text(account == nil ? "Войдите и откройте этот экран заново, чтобы продолжить."
                     : "Сессия изменилась. Откройте этот экран заново, чтобы продолжить.")
                    .font(.ax(.subheadline)).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct ProfileViewerNotice: View {
    @Environment(AppEnvironment.self) private var env
    let viewer: ProfileViewerKey?

    var body: some View {
        if let viewer, viewer != env.session.viewerKey {
            Section {
                Text("Сессия изменилась. Откройте этот экран заново, чтобы продолжить.")
                    .font(.ax(.subheadline)).foregroundStyle(.secondary)
            }
        }
    }
}
