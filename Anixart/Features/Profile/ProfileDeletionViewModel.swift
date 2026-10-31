import Foundation
import AnixartKit

/// Mutation responses are acknowledgements, not deletion status. Always read
/// the status again before allowing the next action or showing a success notice.
@MainActor
@Observable
final class ProfileDeletionViewModel {
    let account: ProfileAccountKey?
    let resource = ProfileResource<ProfileDeletionResponse>()
    private let session: SessionController
    private(set) var isSaving = false
    private(set) var notice: String?
    private(set) var errorMessage: String?
    private var hasConfirmedStatus = false

    init(account: ProfileAccountKey?, session: SessionController) {
        self.account = account
        self.session = session
    }

    var hasCurrentAccount: Bool { account != nil && session.accountKey == account }
    var hasRequest: Bool { resource.value?.hasDeletionRequest == true }
    var mayChange: Bool {
        hasCurrentAccount && hasConfirmedStatus && !isSaving && !resource.isLoading && resource.errorMessage == nil
            && resource.value?.hasDeletionRequest != nil
    }

    func invalidate(for current: ProfileAccountKey?) {
        guard account != current else { return }
        hasConfirmedStatus = false
        resource.reset()
        notice = nil
        errorMessage = nil
    }

    func load() async {
        // A pull-to-refresh must not supersede a mutation's own confirmation.
        guard !isSaving else { return }
        _ = await loadStatus()
    }

    private func loadStatus() async -> ProfileDeletionResponse? {
        guard hasCurrentAccount, !Task.isCancelled, let account else { return nil }
        hasConfirmedStatus = false
        notice = nil
        errorMessage = nil
        let response = await resource.load {
            let response = try await session.sendAccountRequest(ProfileSecurityEndpoints.deletionStatus(), for: account)
            guard response.hasDeletionRequest != nil else {
                throw AnixartError.decoding(message: "Сервер не вернул статус удаления", path: "profile/deletion/status")
            }
            return response
        }
        guard hasCurrentAccount, !Task.isCancelled, let response else { return nil }
        hasConfirmedStatus = true
        return response
    }

    @discardableResult
    func request(password: String) async -> Bool {
        guard mayChange, !hasRequest, !password.isEmpty else { return false }
        return await change(ProfileSecurityEndpoints.requestDeletion(password: password), expectsRequest: true)
    }

    @discardableResult
    func cancel() async -> Bool {
        guard mayChange, hasRequest else { return false }
        return await change(ProfileSecurityEndpoints.cancelDeletion(), expectsRequest: false)
    }

    private func change(_ endpoint: Endpoint<ProfileDeletionResponse>, expectsRequest: Bool) async -> Bool {
        guard !Task.isCancelled, hasCurrentAccount, let account else { return false }
        isSaving = true
        // A cancellation or transport failure can happen after the server has
        // changed the request. Keep the old display, but never act on it again.
        hasConfirmedStatus = false
        errorMessage = nil
        notice = nil
        defer { isSaving = false }
        do {
            let response = try await session.sendAccountRequest(endpoint, for: account)
            guard response.code == 0 else {
                throw AnixartError.decoding(message: "Сервер не подтвердил действие с запросом на удаление", path: endpoint.path)
            }
            resource.reset()
            let confirmed = await loadStatus()
            guard hasCurrentAccount, !Task.isCancelled else { return false }
            guard confirmed?.hasDeletionRequest == expectsRequest else {
                hasConfirmedStatus = false
                errorMessage = expectsRequest
                    ? "Сервер принял запрос, но текущий статус пока не подтверждает его создание. Обновите статус перед повторной отправкой."
                    : "Сервер принял отмену, но текущий статус пока не подтверждает её. Обновите статус перед повторной отправкой."
                return false
            }
            notice = expectsRequest ? "Запрос на удаление создан." : "Запрос на удаление отменён."
            return true
        } catch {
            if hasCurrentAccount, !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
            return false
        }
    }
}
