import Foundation

public enum ChannelEndpoints {
    /// Read-only POST; OwnChannelsPresenter requests permission=1, is_blog=false.
    public static func all(page: Int, request: ChannelsFilterRequest = ChannelsFilterRequest()) -> Endpoint<PageableResponse<Channel>> {
        Endpoint(method: .post, path: "channel/all/\(page)", body: .json(request),
                 auth: request.permission != nil || request.isSubscribed != nil ? .required : .optional)
    }

    public static func search(_ request: ChannelsSearchRequest, page: Int) -> Endpoint<PageableResponse<Channel>> {
        Endpoint(method: .post, path: "search/channels/\(page)", body: .json(request),
                 auth: request.permission != nil || request.isSubscribed != nil ? .required : .optional)
    }

    public static func subscriptions(page: Int, sort: Int = 1) -> Endpoint<PageableResponse<Channel>> {
        Endpoint(path: "channel/subscription/all/\(page)", query: ["sort": String(sort)], auth: .required)
    }

    public static func subscriptionCount() -> Endpoint<SubscriptionCountResponse> {
        Endpoint(path: "channel/subscription/count", auth: .required)
    }

    public static func recommendations(page: Int, isBlog: Bool? = nil, excludeSubscribed: Bool? = nil) -> Endpoint<PageableResponse<Channel>> {
        Endpoint(path: "channel/recommendations/\(page)",
                 query: ["is_blog": isBlog.map { String($0) }, "exclude_subscribed": excludeSubscribed.map { String($0) }])
    }

    public static func subscribe(channelID: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "channel/subscribe/\(channelID)", auth: .required)
    }

    public static func unsubscribe(channelID: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "channel/unsubscribe/\(channelID)", auth: .required)
    }

    public static func hide(channelID: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "channel/mute/\(channelID)", auth: .required)
    }

    /// Mutation, never performed merely by opening the profile/create information.
    public static func createBlog() -> Endpoint<BlogCreateResponse> {
        Endpoint(method: .post, path: "channel/blog/create", auth: .required)
    }

    public static func editorAvailability(channelID: Int, isSuggestion: Bool = false, isEditMode: Bool = false) -> Endpoint<ChannelEditorAvailabilityResponse> {
        Endpoint(path: "channel/\(channelID)/editor/available",
                 query: ["is_suggestion": String(isSuggestion), "is_edit_mode": String(isEditMode)], auth: .required)
    }

    public static func channel(id: Int) -> Endpoint<ChannelResponse> {
        Endpoint(path: "channel/\(id)")
    }

    /// A read-only POST with no body, as declared by ChannelApi.articles.
    public static func articles(channelID: Int, page: Int) -> Endpoint<PageableResponse<Article>> {
        Endpoint(method: .post, path: "channel/\(channelID)/article/all/\(page)")
    }

    public static func blog(profileID: Int) -> Endpoint<ChannelResponse> {
        Endpoint(path: "channel/blog/\(profileID)")
    }

    public static func uploadCover(channelID: Int, jpeg: Data) -> Endpoint<ChannelUploadCoverAvatarResponse> {
        Endpoint(method: .post, path: "channel/cover/upload/\(channelID)", body: .multipart(MultipartBody(parts: [
            .init(name: "image", filename: "cover.jpg", contentType: "image/jpeg", data: jpeg)
        ])), auth: .required)
    }

    public static func deleteCover(channelID: Int) -> Endpoint<ChannelUploadCoverAvatarResponse> {
        Endpoint(method: .post, path: "channel/cover/delete/\(channelID)", auth: .required)
    }

    public static func hidden(page: Int) -> Endpoint<PageableResponse<Channel>> {
        Endpoint(path: "channel/mute/all/\(page)", auth: .required)
    }

    public static func unhide(channelID: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "channel/unmute/\(channelID)", auth: .required)
    }
}
