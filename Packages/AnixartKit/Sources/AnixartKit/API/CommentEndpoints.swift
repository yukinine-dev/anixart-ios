import Foundation

/// `release/comment/*`.
public enum CommentEndpoints {
    /// `sort`: 1 newest, 2 oldest, 3 popular (confirmed menu listener values).
    public static func comments(releaseID: Int, page: Int, sort: Int = 1) -> Endpoint<PageableResponse<ReleaseComment>> {
        Endpoint(path: "release/comment/all/\(releaseID)/\(page)", query: ["sort": String(sort)])
    }

    public static func replies(commentID: Int, page: Int, sort: Int = 2) -> Endpoint<PageableResponse<ReleaseComment>> {
        Endpoint(method: .post, path: "release/comment/replies/\(commentID)/\(page)", query: ["sort": String(sort)])
    }

    public static func byProfile(_ profileID: Int, page: Int, sort: Int = 1) -> Endpoint<PageableResponse<ReleaseComment>> {
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

    /// GET with `1` / `2`; repeat the same arrow to remove the vote.
    public static func vote(commentID: Int, vote: CommentVote) -> Endpoint<StatusResponse> {
        Endpoint(path: "release/comment/vote/\(commentID)/\(vote.rawValue)", auth: .required)
    }

    public static func voters(commentID: Int, page: Int, sort: Int? = nil) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(
            path: "release/comment/votes/\(commentID)/\(page)",
            query: ["sort": sort.map { String($0) }]
        )
    }
}
