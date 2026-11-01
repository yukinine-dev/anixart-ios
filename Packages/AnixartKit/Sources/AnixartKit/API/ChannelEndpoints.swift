import Foundation

public enum ChannelEndpoints {
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
