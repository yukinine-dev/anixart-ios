import Foundation
import AnixartKit

/// The composer never borrows the account of a later sign-in, including a second
/// sign-in to the same profile. Its payload is frozen before the first suspension.
@MainActor
@Observable
final class ProfileCommentDraft {
    private(set) var viewer: ProfileViewerKey?
    var message = ""
    var isSpoiler = false
    var replyingTo: ProfileComment?
    private(set) var isSending = false
    var errorMessage: String?

    init(viewer: ProfileViewerKey? = nil) { self.viewer = viewer }

    @discardableResult
    func captureViewer(_ current: ProfileViewerKey) -> ProfileViewerKey {
        if viewer == nil { viewer = current }
        return viewer ?? current
    }

    func invalidate(for current: ProfileViewerKey) {
        guard let viewer, viewer != current else { return }
        clear()
        errorMessage = nil
    }

    private func clear() {
        message = ""
        isSpoiler = false
        replyingTo = nil
    }

    @discardableResult
    func send(at location: ProfileCommentLocation, parentCommentID: Int? = nil,
              defaultReplyToProfileID: Int? = nil, session: SessionController) async -> Bool {
        guard !isSending, let viewer, viewer == session.viewerKey else {
            invalidate(for: session.viewerKey)
            return false
        }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        let originalMessage = message
        let text = originalMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, location.parentID > 0, parentCommentID == nil || (parentCommentID ?? 0) > 0 else { return false }
        let spoiler = isSpoiler
        let target = replyingTo
        let replyTo = target?.profile?.id ?? defaultReplyToProfileID
        guard replyTo == nil || (replyTo ?? 0) > 0 else { return false }
        let request = CommentAddRequest(message: text, parentCommentId: parentCommentID,
                                        replyToProfileId: replyTo,
                                        spoiler: spoiler)
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            // A returned comment ID alone is not a successful acknowledgement.
            // Keep the draft unless the server explicitly confirms this mutation.
            try await session.sendConfirmedAccountRequest(ProfileCommentEndpoints.add(at: location, request: request), for: account)
            guard viewer == session.viewerKey else { invalidate(for: session.viewerKey); return false }
            if message == originalMessage, isSpoiler == spoiler, replyingTo == target { clear() }
            return true
        } catch {
            if viewer != session.viewerKey { invalidate(for: session.viewerKey) }
            else if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
            return false
        }
    }
}
