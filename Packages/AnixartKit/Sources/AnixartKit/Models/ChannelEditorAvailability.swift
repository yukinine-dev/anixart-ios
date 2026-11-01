import Foundation

/// These contracts are known statically. No iOS editor/token bridge is implied.
public struct BlogCreateResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var channel: Channel?
}

public struct ChannelEditorAvailabilityResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var mediaUploadToken: String?
    private enum CodingKeys: String, CodingKey {
        case code
        case mediaUploadToken = "media_upload_token"
    }
}

public enum BlogCreationFailure: Int, Sendable {
    case reputationTooLow = 2
    case creationBanned = 402
}

public enum ChannelEditorFailure: Int, Sendable {
    case temporarilyDisabled = 2
    case limitReached = 3
    case invalidChannel = 4
    case invalidChannelState = 5
    case creatorBanned = 6
    case blogNotCreated = 7
    case channelSuspended = 402
}
