import Foundation

extension ReleaseComment {
    /// The episode that was out when the comment was posted, whichever spelling carried it.
    public var episodeAtPosting: Int? { postedAtEpisode ?? postedAtEpisodeSnake }
}
