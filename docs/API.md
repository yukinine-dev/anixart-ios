# Anixart API, as the Android client calls it

Reverse-engineered from **Anixart 10.5** (`com.swiftsoft.anixartd`, versionCode 26101718) by
decompiling the APK and reading its Retrofit interfaces, with selected response shapes
checked through ordinary public API reads. This describes the server's existing API
so the port can speak to it correctly; no access controls were bypassed.

**300 endpoints** across 42 Retrofit interfaces.

## Conventions

| | |
|---|---|
| Base URL | `https://api-s.anixsekai.com/` (hardcoded fallback; `config/urls` returns the live list) |
| Auth | session token as a **`token` query parameter**, not a header |
| Errors | HTTP 200 with a `code` field in the body: `0` success, `1` failed, `402` banned, `403` permanently banned |
| Paging | zero-based; envelope carries `content`, `current_page`, `total_count`, `total_page_count` |
| Bodies | `auth/*` is `application/x-www-form-urlencoded`; filter, search and report are JSON |
| Reads via POST | `filter/{page}`, `search/*`, `discover/*` are POSTs whose body carries the query |
| Serialisation | Jackson with `@JsonIgnoreProperties(ignoreUnknown = true)`; key casing is **mixed** (see below) |

### Mixed key casing

Most fields are snake_case (`title_ru`, `episodes_released`, `is_favorite`) but some objects
use the Java field name verbatim. `Episode` is the clearest case -- it sends `playbackPosition`
and `addedDate` alongside `is_watched` and `is_filler` in the same object. `SearchRequest`
sends `searchBy`. A blanket `.convertFromSnakeCase` strategy therefore drops fields silently,
which is why `AnixartKit` spells every `CodingKey` out; the mapping was extracted from the
`@JsonProperty` annotations rather than guessed (see `Tools/anixart-10.5-model-map.json`).

### Relations that change shape

Some fields are Room relations in the Android client and the server sends them either as
the whole object or as the bare row id, depending on which endpoint you asked. The one
two found so far are `ReleaseComment.release` (the release object on `discover/comments`,
its id as a number on the comments inlined into `release/{id}?extended_mode=true`) and
`EpisodeSource.type` (the voice-over object in some listings, its id in others).

A model that expects one shape fails the whole response, so `Embedded<T>` decodes either
and says which arrived. Expect other relations to behave the same way; the `probe` job in
CI is what finds them.

### Room row ids are not on the wire

The decompiled models are Room entities, so a `@PrimaryKey` field is not necessarily
something the server sends. `Episode.id` and `ProfileWatchDynamics.id` are assigned
locally by the Android app; the server identifies an episode by its `position` within a
source. Generating those as a required `id` failed the whole response, which is what
broke the episode list and the profile page. They are dropped from the generated types
and their identity is declared in `Models/RoomEntities.swift`.

A server-assigned id (`Release.id`, `Profile.id`, `ReleaseComment.id`) stays required, so
a payload that really is malformed still fails loudly instead of decoding to a silent
nil that collides with every other nil.

### Enum values read out of the APK

| Meaning | Values | Source |
|---|---|---|
| Watch list | 1 watching, 2 plan, 3 completed, 4 hold on, 5 dropped | `DataPreferenceFragment` |
| Bookmark sort | 1/2 added desc/asc, 3/4 release date, 5/6 title, 7/8 rating | `ExtraBookmarksModel` |
| Catalogue sort | 0 updated, 1 grade, 2 year, 3 popularity (desc); +4 for ascending | `FilterRequest` |
| Genres mode | 0 all, 1 any, 2 exclude | `FilterRequest` |
| Episode count preset | 1 <13, 2 13+, 3 26+, 4 100+ | `FilterRequest` |
| Release age rating | 1 `0+`, 2 `6+`, 3 `12+`, 4 `16+`, 5 `18+`; distinct from filter picker indexes | `ReleaseFragment.onReleaseLoaded` / `arrays.xml` |
| Release `searchBy` | 0 titles, 1 studio, 2 director, 3 author, 5 source material | `MainActivity` fact-link handlers → `ReleaseSearchFragment` |
| Notification kind | `episode`, `friend`, `releaseComment`, `collectionComment`, `myCollection`, `article`, `articleComment`, `myArticle`, `relatedRelease` | `ProfileNotification` `@JsonSubTypes` |

Season (`1` winter ... `4` autumn) and comment sort (`0` newest, `1` oldest, `2` most liked)
are inferred from the UI order rather than confirmed by a constant, and are marked as such
in the Swift source.

## Endpoints

### AchievementApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `achievement/get/{code}` | `AchievementResponse` | `path:code (String)`, `query:badge_id (long)`, `query:token (String)` |
| GET | `achievement/preview/{code}` | `AchievementPreviewResponse` | `path:code (String)` |

### ArticleApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `article/create/{c_id}` | `ArticleCreateEditResponse` | `path:c_id (long)`, `query:token (String)` |
| POST | `article/delete/{a_id}` | `ArticleDeleteResponse` | `path:a_id (long)`, `query:token (String)` |
| GET | `article/edit/pinned/{a_id}` | `ArticleEditPinnedResponse` | `path:a_id (long)`, `query:is_pinned (boolean)`, `query:token (String)` |
| POST | `article/edit/{a_id}` | `ArticleCreateEditResponse` | `path:a_id (long)`, `query:token (String)` |
| POST | `article/event` | `Response` | `query:token (String)` |
| GET | `article/mute/{a_id}` | `ArticleMuteResponse` | `path:a_id (long)`, `query:token (String)` |
| GET | `article/reposts/{a_id}/{page}` | `PageableResponse<Article>` | `path:a_id (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `article/unmute/{a_id}` | `ArticleMuteResponse` | `path:a_id (long)`, `query:token (String)` |
| GET | `article/vote/{a_id}/{vote}` | `Response` | `path:a_id (long)`, `path:vote (int)`, `query:token (String)` |
| POST | `article/votes/{a_id}/{page}` | `PageableResponse<Profile>` | `path:a_id (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `article/{a_id}` | `ArticleResponse` | `path:a_id (long)`, `query:token (String)` |

### ArticleCommentApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `article/comment/add/{articleId}` | `CommentAddResponse<ArticleComment>` | `path:articleId (long)`, `query:token (String)` |
| GET | `article/comment/all/profile/{p_id}/{page}` | `PageableResponse<ArticleComment>` | `path:p_id (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `article/comment/all/{a_id}/popular` | `PageableResponse<ArticleComment>` | `path:a_id (long)`, `query:token (String)` |
| GET | `article/comment/all/{a_id}/{page}` | `PageableResponse<ArticleComment>` | `path:a_id (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `article/comment/delete/{commentId}` | `CommentDeleteResponse` | `path:commentId (long)`, `query:token (String)` |
| POST | `article/comment/edit/{commentId}` | `CommentEditResponse` | `path:commentId (long)`, `query:token (String)` |
| POST | `article/comment/process/{commentId}` | `Response` | `path:commentId (long)`, `query:token (String)` |
| POST | `article/comment/replies/{commentId}/{page}` | `PageableResponse<ArticleComment>` | `path:commentId (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `article/comment/vote/{commentId}/{vote}` | `Response` | `path:commentId (long)`, `path:vote (int)`, `query:token (String)` |
| POST | `article/comment/votes/{commentId}/{page}` | `PageableResponse<Profile>` | `path:commentId (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `article/comment/{articleId}` | `ArticleComment` | `path:articleId (long)`, `query:token (String)` |

### ArticleSuggestionApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `article/suggestion/all/{page}` | `PageableResponse<Article>` | `path:page (int)`, `query:token (String)` |
| POST | `article/suggestion/create/{b_id}` | `ArticleCreateEditResponse` | `path:b_id (long)`, `query:token (String)` |
| POST | `article/suggestion/delete/{a_id}` | `ArticleSuggestionDeleteResponse` | `path:a_id (long)`, `query:token (String)` |
| POST | `article/suggestion/edit/{a_id}` | `ArticleCreateEditResponse` | `path:a_id (long)`, `query:token (String)` |
| POST | `article/suggestion/publish/{a_id}` | `ArticleCreateEditResponse` | `path:a_id (long)`, `query:is_signed (boolean)`, `query:token (String)` |
| GET | `article/suggestion/{a_id}` | `ArticleResponse` | `path:a_id (long)`, `query:token (String)` |

### AuthApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST @FormUrlEncoded | `auth/checkLogin` | `CheckLoginResponse` | `field:login (String)` |
| POST | `auth/firebase` | `FirebaseResponse` | `query:token (String)` |
| POST @FormUrlEncoded | `auth/google` | `GoogleResponse` | `field:googleIdToken (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/google` | `GoogleResponse` | `field:login (String)`, `field:email (String)`, `field:googleIdToken (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/resend` | `ResendResponse` | `field:login (String)`, `field:email (String)`, `field:password (String)`, `field:vkAccessToken (String)`, `field:googleIdToken (String)`, `field:telegramIdToken (String)`, `field:yandexAccessToken (String)`, `field:hash (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/restore` | `RestoreResponse` | `field:data (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/restore/resend` | `RestoreResendResponse` | `field:data (String)`, `field:password (String)`, `field:hash (String)` |
| POST @FormUrlEncoded | `auth/restore/verify` | `RestoreVerifyResponse` | `field:data (String)`, `field:password (String)`, `field:hash (String)`, `field:code (String)` |
| POST @FormUrlEncoded | `auth/signIn` | `SignInResponse` | `field:login (String)`, `field:password (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/signUp` | `SignUpResponse` | `field:login (String)`, `field:email (String)`, `field:password (String)` |
| POST @FormUrlEncoded | `auth/telegram` | `TelegramResponse` | `field:telegramIdToken (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/telegram` | `TelegramResponse` | `field:login (String)`, `field:email (String)`, `field:telegramIdToken (String)` |
| POST @FormUrlEncoded | `auth/verify` | `VerifyResponse` | `field:login (String)`, `field:email (String)`, `field:password (String)`, `field:vkAccessToken (String)`, `field:googleIdToken (String)`, `field:telegramIdToken (String)`, `field:yandexAccessToken (String)`, `field:hash (String)`, `field:code (String)` |
| POST @FormUrlEncoded | `auth/vk` | `VkResponse` | `field:vkAccessToken (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/vk` | `VkResponse` | `field:login (String)`, `field:email (String)`, `field:vkAccessToken (String)` |
| POST @FormUrlEncoded | `auth/yandex` | `YandexResponse` | `field:yandexAccessToken (String)` |
| POST @FormUrlEncoded @Headers({"X-Long-Code: 1"}) | `auth/yandex` | `YandexResponse` | `field:login (String)`, `field:email (String)`, `field:yandexAccessToken (String)` |

### ChannelApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `channel/all/{page}` | `PageableResponse<Channel>` | `path:page (int)`, `query:token (String)` |
| POST @Multipart | `channel/avatar/upload/{c_id}` | `ChannelUploadCoverAvatarResponse` | `path:c_id (long)`, `query:token (String)` |
| POST | `channel/blog/create` | `BlogCreateResponse` | `query:token (String)` |
| GET | `channel/blog/{p_id}` | `ChannelResponse` | `path:p_id (long)`, `query:token (String)` |
| POST | `channel/cover/delete/{c_id}` | `ChannelUploadCoverAvatarResponse` | `path:c_id (long)`, `query:token (String)` |
| POST @Multipart | `channel/cover/upload/{c_id}` | `ChannelUploadCoverAvatarResponse` | `path:c_id (long)`, `query:token (String)` |
| POST | `channel/create` | `ChannelCreateEditResponse` | `query:token (String)` |
| POST | `channel/delete/{c_id}` | `ChannelDeleteResponse` | `path:c_id (long)`, `query:token (String)` |
| POST | `channel/edit/{c_id}` | `ChannelCreateEditResponse` | `path:c_id (long)`, `query:token (String)` |
| GET | `channel/editor/available/all` | `EditorChannelsResponse` | `query:token (String)`, `query:only_subscribed (Boolean)` |
| GET | `channel/mute/all/{page}` | `PageableResponse<Channel>` | `path:page (int)`, `query:token (String)` |
| POST | `channel/mute/{c_id}` | `ArticleMuteResponse` | `path:c_id (long)`, `query:token (String)` |
| GET | `channel/recommendations/{page}` | `PageableResponse<Channel>` | `path:page (int)`, `query:token (String)`, `query:is_blog (Boolean)`, `query:exclude_subscribed (Boolean)` |
| POST | `channel/subscribe/{c_id}` | `ChannelSubscribeResponse` | `path:c_id (long)`, `query:token (String)` |
| GET | `channel/subscription/all/{page}` | `PageableResponse<Channel>` | `path:page (int)`, `query:token (String)`, `query:sort (int)` |
| GET | `channel/subscription/count` | `SubscriptionCountResponse` | `query:token (String)` |
| POST | `channel/unmute/{c_id}` | `ArticleMuteResponse` | `path:c_id (long)`, `query:token (String)` |
| POST | `channel/unsubscribe/{c_id}` | `ChannelUnsubscribeResponse` | `path:c_id (long)`, `query:token (String)` |
| GET | `channel/{c_id}` | `ChannelResponse` | `path:c_id (long)`, `query:token (String)` |
| POST | `channel/{c_id}/article/all/{page}` | `PageableResponse<Article>` | `path:c_id (long)`, `path:page (int)`, `query:token (String)` |
| GET | `channel/{c_id}/block/all/{page}` | `PageableResponse<ChannelProfile>` | `path:c_id (long)`, `path:page (int)`, `query:token (String)` |
| POST | `channel/{c_id}/block/manage` | `ChannelBlockResponse` | `path:c_id (long)`, `query:token (String)` |
| GET | `channel/{c_id}/block/{p_id}` | `ChannelBlockResponse` | `path:c_id (long)`, `path:p_id (long)`, `query:token (String)` |
| GET | `channel/{c_id}/editor/available` | `EditorAvailableResponse` | `path:c_id (long)`, `query:is_suggestion (boolean)`, `query:is_edit_mode (boolean)`, `query:token (String)` |
| POST | `channel/{c_id}/permission/all/{page}` | `PageableResponse<ChannelProfile>` | `path:c_id (long)`, `path:page (int)`, `query:token (String)` |
| POST | `channel/{c_id}/permission/manage` | `ChannelPermissionManageResponse` | `path:c_id (long)`, `query:token (String)` |

### CollectionApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `collection/all/profile/{p_id}/{page}` | `PageableResponse<Collection>` | `path:p_id (long)`, `path:page (int)`, `query:token (String)` |
| GET | `collection/all/release/{r_id}/{page}` | `PageableResponse<Collection>` | `path:r_id (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `collection/all/{page}` | `PageableResponse<Collection>` | `path:page (int)`, `query:previous_page (int)`, `query:where (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `collection/{id}` | `CollectionResponse` | `path:id (long)`, `query:token (String)` |
| GET | `collection/{id}/releases/{page}` | `PageableResponse<Release>` | `path:id (long)`, `path:page (int)`, `query:token (String)` |

### CollectionCommentApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `collection/comment/add/{collectionId}` | `CommentAddResponse<CollectionComment>` | `path:collectionId (long)`, `query:token (String)` |
| GET | `collection/comment/all/profile/{p_id}/{page}` | `PageableResponse<CollectionComment>` | `path:p_id (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `collection/comment/all/{collectionId}/{page}` | `PageableResponse<CollectionComment>` | `path:collectionId (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `collection/comment/delete/{commentId}` | `CommentDeleteResponse` | `path:commentId (long)`, `query:token (String)` |
| POST | `collection/comment/edit/{commentId}` | `CommentEditResponse` | `path:commentId (long)`, `query:token (String)` |
| POST | `collection/comment/process/{commentId}` | `Response` | `path:commentId (long)`, `query:token (String)` |
| POST | `collection/comment/replies/{commentId}/{page}` | `PageableResponse<CollectionComment>` | `path:commentId (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `collection/comment/vote/{commentId}/{vote}` | `Response` | `path:commentId (long)`, `path:vote (int)`, `query:token (String)` |
| GET | `collection/comment/votes/{commentId}/{page}` | `PageableResponse<Profile>` | `path:commentId (long)`, `path:page (int)`, `query:sort (Integer)`, `query:token (String)` |
| GET | `collection/comment/{collectionId}` | `CollectionComment` | `path:collectionId (long)`, `query:token (String)` |

### CollectionFavoriteApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `collectionFavorite/add/{id}` | `FavoriteCollectionAddResponse` | `path:id (long)`, `query:token (String)` |
| GET | `collectionFavorite/all/{page}` | `PageableResponse<Collection>` | `path:page (int)`, `query:token (String)` |
| GET | `collectionFavorite/delete/{id}` | `FavoriteCollectionDeleteResponse` | `path:id (long)`, `query:token (String)` |

### CollectionMyApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `collectionMy/create` | `CollectionCreateEditResponse` | `query:token (String)` |
| GET | `collectionMy/delete/{collectionId}` | `CollectionDeleteResponse` | `path:collectionId (long)`, `query:token (String)` |
| POST | `collectionMy/edit/{collectionId}` | `CollectionCreateEditResponse` | `path:collectionId (long)`, `query:token (String)` |
| POST @Multipart | `collectionMy/editImage/{collectionId}` | `CollectionEditImageResponse` | `path:collectionId (long)`, `query:token (String)` |
| GET | `collectionMy/release/add/{collectionId}` | `ReleaseAddCollectionResponse` | `path:collectionId (long)`, `query:release_id (long)`, `query:token (String)` |
| GET | `collectionMy/{id}/releases` | `PageableResponse<Release>` | `path:id (long)`, `query:token (String)` |

### ConfigApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `config/anixplayer` | `AnixPlayerConfigResponse` | — |
| GET | `config/toggles` | `TogglesResponse` | `query:version_code (int)`, `query:is_beta (boolean)`, `query:is_api_alt (boolean)`, `query:token (String)` |
| GET | `config/urls` | `ConfigUrlsResponse` | `query:version_code (int)`, `query:is_beta (boolean)`, `query:token (String)` |

### DiscoverApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `discover/comments` | `PageableResponse<ReleaseComment>` | — |
| POST | `discover/discussing` | `PageableResponse<Release>` | `query:token (String)` |
| POST | `discover/interesting` | `PageableResponse<Interesting>` | — |
| POST | `discover/recommendations/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:previous_page (int)`, `query:token (String)` |
| POST | `discover/watching/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:token (String)` |

### EpisodeApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `episode/target/{releaseId}/{sourceId}/{position}` | `EpisodeTargetResponse` | `path:releaseId (long)`, `path:sourceId (long)`, `path:position (int)` |
| POST | `episode/unwatch/{releaseId}/{sourceId}` | `EpisodeUnwatchResponse` | `path:releaseId (long)`, `path:sourceId (long)`, `query:token (String)` |
| POST | `episode/unwatch/{releaseId}/{sourceId}/{position}` | `EpisodeUnwatchResponse` | `path:releaseId (long)`, `path:sourceId (long)`, `path:position (int)`, `query:token (String)` |
| GET | `episode/updates/{releaseId}/{page}` | `PageableResponse<EpisodeUpdate>` | `path:releaseId (long)`, `path:page (int)` |
| POST | `episode/watch/{releaseId}/{sourceId}` | `EpisodeWatchResponse` | `path:releaseId (long)`, `path:sourceId (long)`, `query:token (String)` |
| POST | `episode/watch/{releaseId}/{sourceId}/{position}` | `EpisodeWatchResponse` | `path:releaseId (long)`, `path:sourceId (long)`, `path:position (int)`, `query:token (String)` |
| GET | `episode/{releaseId}` | `TypesResponse` | `path:releaseId (long)`, `query:token (String)` |
| GET | `episode/{releaseId}/{typeId}` | `SourcesResponse` | `path:releaseId (long)`, `path:typeId (long)` |
| GET | `episode/{releaseId}/{typeId}/{sourceId}` | `EpisodeResponse` | `path:releaseId (long)`, `path:typeId (long)`, `path:sourceId (long)`, `query:sort (int)`, `query:token (String)` |

### ExportApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `export/bookmarks` | `BookmarksExportResponse` | `query:sort (Integer)`, `query:token (String)` |

### FavoriteApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `favorite/add/{r_id}` | `FavoritesResponse` | `path:r_id (long)`, `query:token (String)` |
| GET | `favorite/all/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:sort (Integer)`, `query:filter_announce (Integer)`, `query:token (String)` |
| GET | `favorite/delete/{r_id}` | `FavoritesResponse` | `path:r_id (long)`, `query:token (String)` |

### FeedApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `feed/all/{page}` | `PageableResponse<Article>` | `path:page (int)`, `query:channel_id (Long)`, `query:date (int)`, `query:token (String)` |
| GET | `feed/latest` | `LatestArticleResponse` | `query:token (String)` |
| GET | `feed/latest/all/{page}` | `PageableResponse<Article>` | `path:page (int)`, `query:token (String)` |

### FilterApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `filter/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:extended_mode (Boolean)`, `query:token (String)` |

### HistoryApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `history/add/{r_id}/{s_id}/{position}` | `HistoryResponse` | `path:r_id (long)`, `path:s_id (long)`, `path:position (int)`, `query:token (String)` |
| GET | `history/delete/{r_id}` | `HistoryResponse` | `path:r_id (long)`, `query:token (String)` |
| GET | `history/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:token (String)` |

### ImportApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `import/bookmarks` | `BookmarksImportResponse` | `query:token (String)` |
| POST | `import/status` | `BookmarksImportStatusResponse` | `query:token (String)` |

### NotificationApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `notification/all/{page}` | `PageableResponse<ProfileNotification>` | `path:page (int)`, `query:token (String)` |
| GET | `notification/article/comments/{page}` | `PageableResponse<ProfileArticleCommentNotification>` | `path:page (int)`, `query:token (String)` |
| GET | `notification/article/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/articleComment/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/articles/{page}` | `PageableResponse<ProfileArticleNotification>` | `path:page (int)`, `query:token (String)` |
| GET | `notification/collectionComment/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/collectionComments/{page}` | `PageableResponse<ProfileCollectionCommentNotification>` | `path:page (int)`, `query:token (String)` |
| GET | `notification/count` | `NotificationCountResponse` | `query:token (String)` |
| GET | `notification/delete/all` | `Response` | `query:token (String)` |
| GET | `notification/episode/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/episodes/{page}` | `PageableResponse<ProfileEpisodeNotification>` | `path:page (int)`, `query:token (String)` |
| GET | `notification/friend/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/friends/{page}` | `PageableResponse<ProfileFriendNotification>` | `path:page (int)`, `query:token (String)` |
| GET | `notification/my/article/comment/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/my/collection/comment/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/read` | `Response` | `query:token (String)` |
| GET | `notification/related/release/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/related/release/{page}` | `PageableResponse<ProfileRelatedReleaseNotification>` | `path:page (int)`, `query:token (String)` |
| GET | `notification/releaseComment/delete/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `notification/releaseComments/{page}` | `PageableResponse<ProfileReleaseCommentNotification>` | `path:page (int)`, `query:token (String)` |

### NotificationPreferenceApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/preference/notification/article/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/comment/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/episode/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/episode/first/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/my` | `NotificationPreferenceResponse` | `query:token (String)` |
| GET | `profile/preference/notification/my/article/comment/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/my/collection/comment/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/related/release/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/release/all/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:token (String)` |
| POST | `profile/preference/notification/release/type/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/release/type/{releaseId}` | `ProfileReleaseTypeNotificationPreferencesResponse` | `path:releaseId (long)`, `query:token (String)` |
| GET | `profile/preference/notification/report/process/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/notification/selected/releases/edit` | `Response` | `query:token (String)` |
| POST | `profile/preference/notification/status/edit` | `Response` | `query:token (String)` |
| POST | `profile/preference/notification/type/edit` | `Response` | `query:token (String)` |

### ProfileApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/info` | `ProfileInfoResponse` | `query:token (String)` |
| GET | `profile/login/history/all/{id}/{page}` | `PageableResponse<ChangeLogin>` | `path:id (long)`, `path:page (int)`, `query:token (String)` |
| POST | `profile/process/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `profile/social/{id}` | `ProfileSocialResponse` | `path:id (long)`, `query:token (String)` |
| GET | `profile/{id}` | `ProfileResponse` | `path:id (long)`, `query:token (String)` |

### ProfileBadgeApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/preference/badge/edit/{id}` | `ProfileBadgeResponse` | `path:id (long)`, `query:token (String)` |
| GET | `profile/preference/badge/remove` | `Response` | `query:token (String)` |
| POST | `profile/preference/badge/showcase/pin/{id}` | `ProfileBadgeShowcaseResponse` | `path:id (long)`, `query:token (String)` |
| POST | `profile/preference/badge/showcase/reorder` | `ProfileBadgeShowcaseResponse` | `query:token (String)` |
| POST | `profile/preference/badge/showcase/unpin/{id}` | `ProfileBadgeShowcaseResponse` | `path:id (long)`, `query:token (String)` |
| GET | `profile/{id}/badge/list` | `ProfileBadgeSectionsResponse` | `path:id (long)`, `query:recent (String)`, `query:token (String)` |
| GET | `profile/{id}/badge/list/{categoryId}/{page}` | `ProfileBadgePageableResponse<Badge>` | `path:id (long)`, `path:categoryId (long)`, `path:page (int)`, `query:token (String)` |

### ProfileBlockListApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/blocklist/add/{id}` | `BlockProfileListAddResponse` | `path:id (long)`, `query:token (String)` |
| GET | `profile/blocklist/all/{page}` | `PageableResponse<Profile>` | `path:page (int)`, `query:token (String)` |
| GET | `profile/blocklist/remove/{id}` | `Response` | `path:id (long)`, `query:token (String)` |

### ProfileDeletionApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `profile/deletion/cancel` | `ProfileDeletionResponse` | `query:token (String)` |
| POST @FormUrlEncoded | `profile/deletion/request` | `ProfileDeletionResponse` | `query:token (String)`, `field:password (String)` |
| GET | `profile/deletion/status` | `ProfileDeletionResponse` | `query:token (String)` |

### ProfileFriendApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/friend/all/{id}/{page}` | `PageableResponse<Profile>` | `path:id (long)`, `path:page (int)`, `query:token (String)` |
| GET | `profile/friend/recommendations` | `PageableResponse<Profile>` | `query:token (String)` |
| GET | `profile/friend/request/hide/{id}` | `Response` | `path:id (long)`, `query:token (String)` |
| GET | `profile/friend/request/remove/{id}` | `RemoveFriendRequestResponse` | `path:id (long)`, `query:token (String)` |
| GET | `profile/friend/request/send/{id}` | `SendFriendRequestResponse` | `path:id (long)`, `query:token (String)` |
| GET | `profile/friend/requests/in/last` | `PageableResponse<Profile>` | `query:count (int)`, `query:token (String)` |
| GET | `profile/friend/requests/in/{page}` | `PageableResponse<Profile>` | `path:page (int)`, `query:token (String)` |
| GET | `profile/friend/requests/out/last` | `PageableResponse<Profile>` | `query:count (int)`, `query:token (String)` |
| GET | `profile/friend/requests/out/{page}` | `PageableResponse<Profile>` | `path:page (int)`, `query:token (String)` |

### ProfileHealthApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/health/enforcement/account/all/{page}` | `List<ProfileEnforcement>` | `path:page (int)`, `query:token (String)` |
| GET | `profile/health/enforcement/content/all/{page}` | `List<ProfileEnforcement>` | `path:page (int)`, `query:token (String)` |
| GET | `profile/health/enforcement/{id}` | `ProfileEnforcementResponse` | `path:id (long)`, `query:token (String)` |
| POST | `profile/health/enforcement/{id}/appeal` | `ProfileEnforcementAppealResponse` | `path:id (long)`, `query:token (String)` |
| GET | `profile/health/status` | `ProfileHealthStatusResponse` | `query:token (String)` |

### ProfileListApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/list/add/{status}/{r_id}` | `ProfileListResponse` | `path:status (int)`, `path:r_id (long)`, `query:token (String)` |
| GET | `profile/list/all/{p_id}/{status}/{page}` | `PageableResponse<Release>` | `path:p_id (long)`, `path:status (int)`, `path:page (int)`, `query:sort (Integer)`, `query:filter_announce (Integer)`, `query:token (String)` |
| GET | `profile/list/all/{status}/{page}` | `PageableResponse<Release>` | `path:status (int)`, `path:page (int)`, `query:sort (Integer)`, `query:filter_announce (Integer)`, `query:token (String)` |
| GET | `profile/list/delete/{status}/{r_id}` | `ProfileListResponse` | `path:status (int)`, `path:r_id (long)`, `query:token (String)` |

### ProfilePreferenceApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `profile/preference/avatar/delete` | `ProfilePreferenceResponse` | `query:token (String)` |
| POST @Multipart | `profile/preference/avatar/edit` | `ProfilePreferenceResponse` | `query:token (String)` |
| POST @FormUrlEncoded | `profile/preference/email/change` | `ChangeEmailResponse` | `field:current_email (String)`, `field:current_password (String)`, `field:new_email (String)`, `query:token (String)`, `header:API-Version (String)` |
| POST @FormUrlEncoded | `profile/preference/email/resend` | `ChangeEmailResendResponse` | `field:new_email (String)`, `field:current_email (String)`, `field:current_password (String)`, `field:hash (String)`, `query:token (String)` |
| GET | `profile/preference/email/verify` | `ChangeEmailVerifyResponse` | `query:new_email (String)`, `query:code (int)`, `query:hash (String)`, `query:token (String)` |
| POST | `profile/preference/episode-widget/edit` | `Response` | `query:hidden (boolean)`, `query:token (String)` |
| POST @FormUrlEncoded | `profile/preference/google/bind` | `GoogleBindResponse` | `field:idToken (String)`, `query:token (String)` |
| POST | `profile/preference/google/unbind` | `GoogleUnbindResponse` | `query:token (String)` |
| POST | `profile/preference/login/change` | `ChangeLoginResponse` | `query:login (String)`, `query:token (String)` |
| POST | `profile/preference/login/history/delete` | `Response` | `query:token (String)` |
| POST | `profile/preference/login/info` | `ChangeLoginInfoResponse` | `query:token (String)` |
| GET | `profile/preference/my` | `ProfilePreferenceResponse` | `query:token (String)` |
| POST @FormUrlEncoded | `profile/preference/password/change` | `ChangePasswordResponse` | `field:current (String)`, `field:new (String)`, `query:token (String)` |
| POST | `profile/preference/privacy/counts/edit` | `Response` | `query:token (String)` |
| POST | `profile/preference/privacy/friendRequests/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/privacy/incognito/edit` | `Response` | `query:token (String)` |
| POST | `profile/preference/privacy/social/edit` | `Response` | `query:token (String)` |
| POST | `profile/preference/privacy/stats/edit` | `Response` | `query:token (String)` |
| POST | `profile/preference/section/edit` | `Response` | `query:token (String)` |
| GET | `profile/preference/social` | `ProfileSocialResponse` | `query:token (String)` |
| POST | `profile/preference/social/edit` | `SocialEditResponse` | `query:token (String)` |
| POST | `profile/preference/status/edit` | `ProfilePreferenceResponse` | `query:token (String)` |
| POST @FormUrlEncoded | `profile/preference/telegram/bind` | `TelegramBindResponse` | `field:idToken (String)`, `query:token (String)` |
| POST | `profile/preference/telegram/unbind` | `TelegramUnbindResponse` | `query:token (String)` |
| POST | `profile/preference/themes/edit` | `ProfileSelectThemeResponse` | `query:token (String)` |
| POST @FormUrlEncoded | `profile/preference/vk/bind` | `VkBindResponse` | `field:accessToken (String)`, `query:token (String)` |
| POST | `profile/preference/vk/unbind` | `VkUnbindResponse` | `query:token (String)` |
| POST @FormUrlEncoded | `profile/preference/yandex/bind` | `YandexBindResponse` | `field:accessToken (String)`, `query:token (String)` |
| POST | `profile/preference/yandex/unbind` | `YandexUnbindResponse` | `query:token (String)` |

### ProfileReleaseVoteApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `/profile/vote/release/unvoted/last` | `PageableResponse<Release>` | `query:token (String)` |
| GET | `/profile/vote/release/unvoted/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:token (String)` |
| GET | `/profile/vote/release/voted/{p_id}/{page}` | `PageableResponse<Release>` | `path:p_id (long)`, `path:page (int)`, `query:sort (Integer)`, `query:token (String)` |

### ProfileRoleListApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `role/all/{page}/{role_id}` | `PageableResponse<ProfileRole>` | `path:page (int)`, `path:role_id (long)`, `query:token (String)` |

### RelatedApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `related/{relatedId}/{page}` | `PageableResponse<Release>` | `path:relatedId (long)`, `path:page (int)`, `query:token (String)`, `header:API-Version (String)` |

### ReleaseApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `release/collection/{id}/random` | `ReleaseResponse` | `path:id (long)`, `query:extended_mode (boolean)`, `query:token (String)` |
| GET | `release/random` | `ReleaseResponse` | `query:extended_mode (boolean)`, `query:token (String)` |
| GET | `release/random/favorite` | `ReleaseResponse` | `query:extended_mode (boolean)`, `query:token (String)` |
| GET | `release/random/profile/list/{p_id}/{status}` | `ReleaseResponse` | `path:p_id (long)`, `path:status (int)`, `query:extended_mode (boolean)`, `query:token (String)` |
| GET | `release/vote/add/{r_id}/{vote}` | `VoteReleaseResponse` | `path:r_id (long)`, `path:vote (int)`, `query:token (String)` |
| GET | `release/vote/delete/{r_id}` | `DeleteVoteReleaseResponse` | `path:r_id (long)`, `query:token (String)` |
| GET | `release/{r_id}` | `ReleaseResponse` | `path:r_id (long)`, `query:extended_mode (boolean)`, `query:token (String)` |
| GET | `release/{r_id}/badges/{page}` | `PageableResponse<Badge>` | `path:r_id (long)`, `path:page (int)`, `query:token (String)` |

### ReleaseCommentApi

Comment vote arrows send **`1` (negative) / `2` (positive)**. Repeating the same
arrow toggles the vote off; do not send `0` or `-1`. The returned comment uses
`vote: 0` for no vote. Vote response codes `2` / `3` mean the daily negative-vote
limit / insufficient account age, not invalid login / password. `402` / `403`
remain bans. Verified offline against the supplied 10.5 APK (`ecca1727…82d00`),
including both comments and replies callbacks; this is not iOS runtime evidence.

Text replies use the same **POST `release/comment/add/{releaseId}`** as root
comments, with camelCase `parentCommentId` (thread root) and `replyToProfileId`
(recipient) in the JSON body. Add codes: `2` missing release, `3` missing comment,
`4` missing profile, `5` too short, `6` too long, `7` daily comment limit,
`8` recipient's blocklist (not an account ban). Real `402` / `403` remain bans.

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `release/comment/add/{releaseId}` | `CommentAddResponse<ReleaseComment>` | `path:releaseId (long)`, `query:token (String)` |
| GET | `release/comment/all/profile/{p_id}/{page}` | `PageableResponse<ReleaseComment>` | `path:p_id (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `release/comment/all/{releaseId}/{page}` | `PageableResponse<ReleaseComment>` | `path:releaseId (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `release/comment/delete/{commentId}` | `CommentDeleteResponse` | `path:commentId (long)`, `query:token (String)` |
| POST | `release/comment/edit/{commentId}` | `CommentEditResponse` | `path:commentId (long)`, `query:token (String)` |
| POST | `release/comment/process/{commentId}` | `Response` | `path:commentId (long)`, `query:token (String)` |
| POST | `release/comment/replies/{commentId}/{page}` | `PageableResponse<ReleaseComment>` | `path:commentId (long)`, `path:page (int)`, `query:sort (int)`, `query:token (String)` |
| GET | `release/comment/vote/{commentId}/{vote}` | `Response` | `path:commentId (long)`, `path:vote (int)`, `query:token (String)` |
| GET | `release/comment/votes/{commentId}/{page}` | `PageableResponse<Profile>` | `path:commentId (long)`, `path:page (int)`, `query:sort (Integer)`, `query:token (String)` |
| GET | `release/comment/{releaseId}` | `ReleaseComment` | `path:releaseId (long)`, `query:token (String)` |

### ReleaseStreamingPlatformApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `release/streaming/platform/{releaseId}` | `PageableResponse<ReleaseStreamingPlatform>` | `path:releaseId (long)` |

### ReleaseVideoApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `/video/profile/{p_id}/{page}` | `PageableResponse<ReleaseVideo>` | `path:p_id (long)`, `path:page (int)`, `query:token (String)` |
| GET | `/video/release/categories` | `ReleaseVideoCategoriesResponse` | — |
| GET | `/video/release/{releaseId}` | `ReleaseVideosResponse` | `path:releaseId (long)` |
| GET | `/video/release/{releaseId}/category/{categoryId}/{page}` | `PageableResponse<ReleaseVideo>` | `path:releaseId (long)`, `path:categoryId (long)`, `path:page (int)` |
| GET | `/video/release/{releaseId}/{page}` | `PageableResponse<ReleaseVideo>` | `path:releaseId (long)`, `path:page (int)` |

The full Video hub uses **`/video/release/{releaseId}`**, not its `/{page}`
endpoint. `ReleaseVideosResponse` carries `release`, `blocks` (each with `category`
and `videos`), `last_videos`, `streaming_platforms` and `can_appeal`. These exact
keys came from the APK's Jackson annotations/default field names. `last_videos`
seeds the recent list; subsequent pages use the requested index and raw 25 rule.
`ReleaseVideosUiController` also uses 25 raw block videos as its category Show all
boundary. All three release-video read shapes are token-free and retain the
generic API version; they must not inherit release search's `v2` override.

### ReleaseVideoAppealApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `/video/appeal/add` | `ReleaseVideoAppealResponse` | `query:token (String)` |
| POST | `/video/appeal/delete/{appealId}` | `ReleaseVideoAppealResponse` | `path:appealId (long)`, `query:token (String)` |
| GET | `/video/appeal/profile/last` | `PageableResponse<ReleaseVideo>` | `query:token (String)` |
| GET | `/video/appeal/profile/{page}` | `PageableResponse<ReleaseVideo>` | `path:page (int)`, `query:token (String)` |

### ReleaseVideoFavoriteApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `/releaseVideoFavorite/all/{p_id}/{page}` | `PageableResponse<ReleaseVideo>` | `path:p_id (long)`, `path:page (int)`, `query:token (String)` |
| GET | `releaseVideoFavorite/add/{r_id}` | `FavoritesResponse` | `path:r_id (long)`, `query:token (String)` |
| GET | `releaseVideoFavorite/delete/{r_id}` | `FavoritesResponse` | `path:r_id (long)`, `query:token (String)` |

### ReportApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `report/article` | `ReportResponse` | `query:token (String)` |
| GET | `report/article/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/channel` | `ReportResponse` | `query:token (String)` |
| GET | `report/channel/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/collection` | `ReportResponse` | `query:token (String)` |
| GET | `report/collection/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/comment/article` | `ReportResponse` | `query:token (String)` |
| GET | `report/comment/article/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/comment/collection` | `ReportResponse` | `query:token (String)` |
| GET | `report/comment/collection/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/comment/release` | `ReportResponse` | `query:token (String)` |
| GET | `report/comment/release/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/episode` | `ReportResponse` | `query:token (String)` |
| GET | `report/episode/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/profile` | `ReportResponse` | `query:token (String)` |
| GET | `report/profile/reasons` | `List<ReportReason>` | `query:token (String)` |
| POST | `report/release` | `ReportResponse` | `query:token (String)` |
| GET | `report/release/reasons` | `List<ReportReason>` | `query:token (String)` |

### ScheduleApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `schedule` | `ScheduleResponse` | — |

### SearchApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| POST | `search/articles/{page}` | `PageableResponse<Article>` | `path:page (int)`, `query:token (String)` |
| POST | `search/channel/{c_id}/subscribers/{page}` | `PageableResponse<ChannelProfile>` | `path:c_id (long)`, `path:page (int)`, `query:token (String)` |
| POST | `search/channels/{page}` | `PageableResponse<Channel>` | `path:page (int)`, `query:token (String)` |
| POST | `search/collections/{page}` | `PageableResponse<Collection>` | `path:page (int)`, `query:token (String)` |
| POST | `search/favoriteCollections/{page}` | `PageableResponse<Collection>` | `path:page (int)`, `query:token (String)` |
| POST | `search/favorites/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:token (String)` |
| POST | `search/feed/{page}` | `FeedSearchResponse` | `path:page (int)`, `query:token (String)` |
| POST | `search/history/{page}` | `PageableResponse<Release>` | `path:page (int)`, `query:token (String)` |
| POST | `search/profile/list/{status}/{page}` | `PageableResponse<Release>` | `path:status (int)`, `path:page (int)`, `query:token (String)` |
| POST | `search/profileCollections/{p_id}/{page}` | `PageableResponse<Collection>` | `path:p_id (long)`, `path:page (int)`, `query:release_id (long)`, `query:token (String)` |
| POST | `search/profiles/{page}` | `PageableResponse<Profile>` | `path:page (int)`, `query:token (String)` |
| POST | `search/releases/{page}` | `ReleaseSearchResponse` | `path:page (int)`, `query:token (String)`, `header:API-Version (String)` |

`ReleaseSearchPresenter` explicitly passes **`API-Version: v2`**, not the client's
generic `2`. The v2 response has `releases` and an optional `related` franchise
(including its `description`, `name_ru`, `images`, `release_count`), not a pageable
envelope. Only page zero updates that suggestion. A raw page with at least 25
releases enables the next page; deduplicating repeated IDs must not change this
boundary. `RelatedPresenter` also passes `v2` for `related/{relatedId}/{page}`;
the ID is the franchise ID, not the selected release ID. These values were read
from the original APK DEX on 2 Nov 2026, not inferred from the visible UI order.

The release's **source-material link** also uses release search: `format_source_link`
contains `source#%1$s`, and the listener forwards the source label via `ll1IIlIl`
to `MainActivity.IIl1llI111`. The factory for `ReleaseSearchFragment` receives
`SEARCH_QUERY: <Release.source>` and **`SEARCH_BY: 5`**. Literal reflection
descriptors confirm that factory; the first argument is the APK's static `-602`
XOR the signed literal `0xfda3` (`-605`), which is 5. This is neither a guessed
source-information URL nor a catalogue filter. The iOS route uses the same
`search/releases/{page}` body and `v2` contract while keeping its four title-search
menu choices separate.

Live, token-free reads on 2 Nov 2026 also confirmed that paging metadata is not
uniform. `filter/0` and `filter/1` can both report `current_page: 0` and
`total_page_count: 0` despite returning different full 25-item pages. Related and
video responses also use zero page counts while further pages exist; video
`total_count` can be a running count. Collection-containing responses can instead
report the final page index: a response with `total_page_count: 392` still has 24
items on page 392. Known 25-item browsing routes therefore continue using the raw
response length and the requested page index, before deduplication, rather than
treating these fields as a universal number of pages. The wire DTOs retain the
server values; unrelated paginator callers keep their existing strategy.

### TypeApi

| Method | Path | Returns | Parameters |
|---|---|---|---|
| GET | `type/all` | `TypeResponse` | `query:token (String)` |
| GET | `type/pin/{releaseId}/{typeId}` | `Response` | `path:releaseId (long)`, `path:typeId (long)`, `query:token (String)` |
| GET | `type/unpin/{releaseId}/{typeId}` | `Response` | `path:releaseId (long)`, `path:typeId (long)`, `query:token (String)` |
| GET | `type/widget/hide/{typeId}` | `Response` | `path:typeId (long)`, `query:permanent (boolean)`, `query:token (String)` |
| GET | `type/widget/unhide/{typeId}` | `Response` | `path:typeId (long)`, `query:token (String)` |
| GET | `type/{typeId}/channel` | `TypeChannelResponse` | `path:typeId (long)`, `query:token (String)` |
