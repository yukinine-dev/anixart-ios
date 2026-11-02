import Foundation

/// Routes keep their release/collection/article category even when replies omit a parent.
public enum ProfileCommentEndpoints {
    public static func comment(id: Int, category: ProfileCommentCategory) -> Endpoint<ProfileComment> {
        Endpoint(path: "\(category.rawValue)/comment/\(id)")
    }

    public static func all(at location: ProfileCommentLocation, page: Int, sort: Int = 1) -> Endpoint<PageableResponse<ProfileComment>> {
        Endpoint(path: "\(location.category.rawValue)/comment/all/\(location.parentID)/\(page)", query: ["sort": String(sort)])
    }

    public static func replies(commentID: Int, category: ProfileCommentCategory, page: Int, sort: Int = 2) -> Endpoint<PageableResponse<ProfileComment>> {
        Endpoint(method: .post, path: "\(category.rawValue)/comment/replies/\(commentID)/\(page)", query: ["sort": String(sort)])
    }

    public static func add(at location: ProfileCommentLocation, request: CommentAddRequest) -> Endpoint<CommentAddResponse<ProfileComment>> {
        Endpoint(method: .post, path: "\(location.category.rawValue)/comment/add/\(location.parentID)",
                 body: .json(request), auth: .required)
    }

    public static func vote(commentID: Int, category: ProfileCommentCategory, vote: CommentVote) -> Endpoint<StatusResponse> {
        Endpoint(path: "\(category.rawValue)/comment/vote/\(commentID)/\(vote.rawValue)", auth: .required)
    }

    public static func voters(commentID: Int, category: ProfileCommentCategory, page: Int,
                              filter: ProfileVoterFilter = .all) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(method: category == .articles ? .post : .get,
                 path: "\(category.rawValue)/comment/votes/\(commentID)/\(page)",
                 query: ["sort": String(filter.rawValue)])
    }

    public static func popularArticleComments(articleID: Int) -> Endpoint<PageableResponse<ProfileComment>> {
        Endpoint(path: "article/comment/all/\(articleID)/popular")
    }
}

public enum ArticleEndpoints {
    public static func hide(id: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "article/mute/\(id)", auth: .required)
    }

    public static func unhide(id: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "article/unmute/\(id)", auth: .required)
    }

    public static func article(id: Int) -> Endpoint<ArticleResponse> {
        Endpoint(path: "article/\(id)")
    }

    public static func vote(id: Int, vote: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "article/vote/\(id)/\(vote)", auth: .required)
    }

    public static func voters(id: Int, page: Int, filter: ProfileVoterFilter = .all) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(method: .post, path: "article/votes/\(id)/\(page)", query: ["sort": String(filter.rawValue)])
    }

    public static func reposts(id: Int, page: Int, sort: Int = 1) -> Endpoint<PageableResponse<Article>> {
        Endpoint(path: "article/reposts/\(id)/\(page)", query: ["sort": String(sort)])
    }
}
