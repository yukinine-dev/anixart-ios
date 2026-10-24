import Foundation

/// `release/comment/*`.
public enum CommentEndpoints {
    /// `sort`: 0 newest first, 1 oldest first, 2 most liked (as the Android sort menu offers).
    public static func comments(releaseID: Int, page: Int, sort: Int = 0) -> Endpoint<PageableResponse<ReleaseComment>> {
        Endpoint(path: "release/comment/all/\(releaseID)/\(page)", query: ["sort": String(sort)])
    }

    public static func replies(commentID: Int, page: Int, sort: Int = 0) -> Endpoint<PageableResponse<ReleaseComment>> {
        Endpoint(method: .post, path: "release/comment/replies/\(commentID)/\(page)", query: ["sort": String(sort)])
    }

    public static func byProfile(_ profileID: Int, page: Int, sort: Int = 0) -> Endpoint<PageableResponse<ReleaseComment>> {
        Endpoint(path: "release/comment/all/profile/\(profileID)/\(page)", query: ["sort": String(sort)])
    }

    public static func add(
        releaseID: Int,
        _ request: CommentAddRequest
    ) -> Endpoint<CommentAddResponse<ReleaseComment>> {
        Endpoint(method: .post, path: "release/comment/add/\(releaseID)", body: .json(request), auth: .required)
    }

    public static func edit(commentID: Int, _ request: CommentEditRequest) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "release/comment/edit/\(commentID)", body: .json(request), auth: .required)
    }

    public static func delete(commentID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "release/comment/delete/\(commentID)", auth: .required)
    }

    /// `vote` is `1` to like, `-1` to dislike and `0` to clear.
    public static func vote(commentID: Int, vote: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "release/comment/vote/\(commentID)/\(vote)", auth: .required)
    }

    public static func voters(commentID: Int, page: Int, sort: Int? = nil) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(
            path: "release/comment/votes/\(commentID)/\(page)",
            query: ["sort": sort.map { String($0) }]
        )
    }
}
