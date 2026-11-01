import SwiftUI
import AnixartKit

/// Both reorder routes edit the same local draft. Only Save sends an account
/// request; Cancel, moving a row and opening the screen never write an order.
@MainActor
@Observable
final class ProfileBadgeOrderModel {
    let resource = ProfileResource<ProfileBadgeSectionsResponse>()
    private(set) var badges: [Badge] = []
    private(set) var originalIDs: [Int] = []
    private(set) var isSaving = false
    var errorMessage: String?
    private var loadedAccount: ProfileAccountKey?
    private var generation = 0

    var hasChanges: Bool { badges.map(\.id) != originalIDs }
    var canReorder: Bool {
        loadedAccount != nil && resource.value != nil && resource.errorMessage == nil
            && !resource.isLoading && !isSaving && (2...ProfileEditorRules.showcaseLimit).contains(badges.count)
    }
    var canSave: Bool { canReorder && hasChanges }

    func reset() {
        generation += 1
        resource.reset()
        badges = []
        originalIDs = []
        loadedAccount = nil
        errorMessage = nil
    }

    func load(profileID: Int, account: ProfileAccountKey, session: SessionController) async {
        guard !isSaving, account.profileID == profileID, session.accountKey == account else { return }
        guard let response = await resource.load({
            let response = try await session.sendAccountRequest(ProfileBadgeEndpoints.sections(profileID: profileID), for: account)
            guard response.code == AnixartStatus.successful else {
                throw AnixartError.decoding(message: "Сервер не подтвердил загрузку витрины", path: "profile/\(profileID)/badge/list")
            }
            guard response.profile == nil || response.profile?.id == profileID else {
                throw AnixartError.decoding(message: "Ответ содержит витрину другого профиля", path: "profile/\(profileID)/badge/list")
            }
            guard let showcased = response.showcased else {
                throw AnixartError.decoding(message: "Ответ не содержит закреплённые значки", path: "profile/\(profileID)/badge/list")
            }
            let ids = showcased.map(\.id)
            guard ids.count <= ProfileEditorRules.showcaseLimit, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else {
                throw AnixartError.decoding(message: "Сервер вернул некорректный порядок значков", path: "profile/\(profileID)/badge/list")
            }
            return response
        }), session.accountKey == account, !Task.isCancelled else { return }
        badges = (response.showcased ?? []).map { ProfileBadgePresentation.resolved($0, in: response) }
        originalIDs = badges.map(\.id)
        loadedAccount = account
        errorMessage = nil
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard canReorder, offsets.allSatisfy({ badges.indices.contains($0) }), (0...badges.count).contains(destination) else { return }
        badges.move(fromOffsets: offsets, toOffset: destination)
    }

    func move(id: Int, by offset: Int) {
        guard canReorder, let index = badges.firstIndex(where: { $0.id == id }), offset == -1 || offset == 1,
              badges.indices.contains(index + offset) else { return }
        badges.swapAt(index, index + offset)
    }

    func cancelChanges() {
        guard !isSaving else { return }
        let byID = Dictionary(badges.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        badges = originalIDs.compactMap { byID[$0] }
        errorMessage = nil
    }

    @discardableResult
    func save(profileID: Int, account: ProfileAccountKey, session: SessionController) async -> Bool {
        guard canSave, loadedAccount == account, account.profileID == profileID, session.accountKey == account,
              Set(badges.map(\.id)) == Set(originalIDs) else { return false }
        let saved = badges
        let requestGeneration = generation
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.reorder(ids: saved.map(\.id)), for: account)
            guard requestGeneration == generation, session.accountKey == account else { return false }
            // Acknowledged order is already saved, even if its following profile
            // refresh is cancelled. Do not offer to submit the same draft twice.
            originalIDs = saved.map(\.id)
            if var response = resource.value {
                response.showcased = saved
                resource.adopt(response)
            }
            await session.refreshProfile(for: account)
            return requestGeneration == generation && session.accountKey == account && !Task.isCancelled
        } catch {
            if requestGeneration == generation, session.accountKey == account, !ProfileRequestFailure.isCancellation(error) {
                errorMessage = Paginator<Release>.message(for: error)
            }
            return false
        }
    }
}
