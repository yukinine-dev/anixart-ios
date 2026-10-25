import Foundation

// The Android models are Room entities, so some of their primary keys are local
// row ids that the server never puts on the wire. Generating those as a required
// `id` made the whole response fail to decode; they are dropped from the
// generated types instead, and the identity the server *does* provide is
// declared here.

extension Episode: Identifiable {
    /// Within one voice-over and hosting an episode is identified by its
    /// position, which is also what `episode/watch/...` and the progress
    /// endpoints address it by.
    public var id: Int {
        position ?? url?.hashValue ?? 0
    }
}

extension ProfileWatchDynamics: Identifiable {
    /// A point on the profile's watch chart, one per day.
    public var id: Int {
        timestamp ?? day ?? 0
    }
}
