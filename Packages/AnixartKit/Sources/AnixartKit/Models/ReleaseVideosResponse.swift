import Foundation

/// Original ReleaseVideosResponse/ReleaseVideoBlock Jackson contract. The hub
/// is not a pageable response: last_videos seeds the separate paged video list.
/// Kept outside Generated; these response types were not in the generated map.
public struct ReleaseVideosResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var release: Release?
    public var blocks: [ReleaseVideoBlock]?
    public var streamingPlatforms: [ReleaseStreamingPlatform]?
    public var lastVideos: [ReleaseVideo]?
    public var canAppeal: Bool?

    public enum CodingKeys: String, CodingKey {
        case code, release, blocks
        case streamingPlatforms = "streaming_platforms"
        case lastVideos = "last_videos"
        case canAppeal = "can_appeal"
    }
}

public struct ReleaseVideoBlock: Codable, Hashable, Sendable {
    public var category: ReleaseVideoCategory?
    public var videos: [ReleaseVideo]?
}
