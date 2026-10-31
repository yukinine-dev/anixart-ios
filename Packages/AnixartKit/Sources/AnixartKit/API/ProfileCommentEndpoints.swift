import Foundation

/// Routes keep their release/collection/article category even when replies omit a parent.
public enum ProfileCommentEndpoints {
    public static func comment(id: Int, category: ProfileCommentCategory) -> Endpoint<ProfileComment> {
        Endpoint(path: "\(category.rawValue)/comment/\(id)")
    }

    public static func all(at location: ProfileCommentLocation, page: Int, sort: Int = 1) -> Endpoint<PageableResponse<ProfileComment>> {
        Endpoint(path: "\(location.category.rawValue)/comment/all/\(location.parentID)/\(page)", query: ["sort": String(sort)])
    }

    public static func replies(commentID: Int, category: ProfileCommentCategory, page: Int, sort: Int = 1) -> Endpoint<PageableResponse<ProfileComment>> {
        Endpoint(method: .post, path: "\(category.rawValue)/comment/replies/\(commentID)/\(page)", query: ["sort": String(sort)])
    }

    public static func add(at location: ProfileCommentLocation, request: CommentAddRequest) -> Endpoint<CommentAddResponse<ProfileComment>> {
        Endpoint(method: .post, path: "\(location.category.rawValue)/comment/add/\(location.parentID)",
                 body: .json(request), auth: .required)
    }

    public static func vote(commentID: Int, category: ProfileCommentCategory, vote: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "\(category.rawValue)/comment/vote/\(commentID)/\(vote)", auth: .required)
    }
}

public enum ArticleEndpoints {
    public static func article(id: Int) -> Endpoint<ArticleResponse> {
        Endpoint(path: "article/\(id)")
    }
}
