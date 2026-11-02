# Porting notes: Android → iOS

How the Android app (`com.swiftsoft.anixartd` 10.5) maps onto this port, what was left out,
and the decisions that are worth knowing before changing anything.

## Architecture

| Android | iOS |
|---|---|
| Retrofit + RxJava `Observable` | `AnixartClient` actor + `async`/`await` |
| Moxy MVP presenters | `@Observable` view models on `@MainActor` |
| Fragments + FragNav, Epoxy controllers | SwiftUI views, `NavigationStack` |
| Hilt/Dagger | one `AppEnvironment`, injected with `.environment(_:)` |
| Room entities doubling as DTOs | `Codable` DTOs only; nothing persisted yet |
| Glide | `AsyncImage` |
| ExoPlayer | `AVPlayer` for direct URLs, `WKWebView` for `iframe` episodes |
| `Prefs` (SharedPreferences) holding the token | keychain (`KeychainTokenStore`) |

The Android entities are Room `@Entity` classes used directly as network DTOs, which is why
several carry fields the server never sends (`lastSetFavoriteDate` and friends, used for local
sort). Those are dropped here — the port has no local database, so they have no meaning.

## Things the API does that shape the client

**Token as a query parameter.** Every authenticated call appends `?token=...`.
`Endpoint.auth` has three states rather than two: `.none` (never send it — some endpoints like
`episode/{releaseId}/{typeId}` take no token at all), `.optional` (send if signed in; the call
works for guests), and `.required` (fail fast with `notAuthenticated`). Getting this wrong is
invisible until a guest sees an empty screen, so it is encoded per endpoint.

**Errors in the body.** A failed call is still HTTP 200. Everything that extends `Response`
in the APK conforms to `AnixartResponse` here, and the client turns a non-zero `code` into
`AnixartError.api` after decoding.

**Mixed key casing.** See `docs/API.md`. The practical consequence: `CodingKeys` are generated
from the APK's annotations and the generated files should not be hand-edited — re-run
`Tools/generate-models.py` instead.

**Polymorphic notifications.** `ProfileNotification` is a Jackson type hierarchy keyed on a
`type` string, with a `defaultImpl` for unknown kinds. `AnixartNotification` mirrors that
including the fallback case, so a kind added server-side degrades to a plain row instead of
failing the whole page.

**Two independent bookmark concepts.** The five watch lists are mutually exclusive
(`profile/list/add` moves a release between them), while `favorite/add` is a separate flag. A
release can be in "Watching" *and* favourited. The UI keeps them separate for that reason.

**Three-level playback.** Voice-over type → hosting source → episode list, each its own
request. `EpisodePickerViewModel` holds all three so switching voice-over does not lose the
user's place.

## Feature coverage

### Implemented

| Area | Screens | Notes |
|---|---|---|
| Главная | tab strip, nine tabs | Моя вкладка has its separate four-field device-local settings (country, category, genres, excluded lists), plus the eight APK filter presets. tabSettings exposes default selection and custom settings; ordinary switching never rewrites the launch default. Long-press remains an additional default shortcut |
| Discover | обзор feed and browsing shortcuts | banners, Обсуждаемое сегодня with daily comment counts, continue watching, recommendations and comments of the week; blocks load concurrently. Partial refresh failures keep existing data and expose retry. Popular, Schedule, Collections, Filter and Random routes use existing typed endpoints |
| Search/filter | full filter, search, native voice input, local Home query history | browsing stays under Home/Discover/search, with no Catalogue root tab. Full `FilterRequest`: sort, country, studio, source material, category, status, season, years, episode count/duration, age rating, genres with all three match modes, voice-over, excluded account lists. Release search pages by the APK's raw 25-item rule, preserves page-zero franchise metadata and exposes same-page retry. Voice input is explicit, permission-aware and scoped to the current query/viewer/scene; the bounded query history has separate account/guest storage and explicit clear/remove |
| Release | detail, titles, video hub/categories, streaming platforms, collections | poster over its own blurred backdrop, the list/bookmark/comments row, Воспроизвести with the last added episode under it, the icon fact lines, genre and source-material search links, description with Подробнее, Видео banners and full hub, rating histogram with star voting, В списках у людей, full-screen Кадры, Связанные релизы, the collection links, Рекомендуем также and the comment preview |
| Playback | "Выберите вариант", episode list, player | the voice-over list with the Все/Озвучки/Субтитры filter, episode and view counts, and the СУБТИТРЫ and НОВИНКА badges; then the hosting picker and episodes. `AVPlayer` for direct URLs, `WKWebView` for `iframe` episodes; watched marks, resume, progress reporting |
| Bookmarks | 8 tabs | third root-tab slot; collections, history, favourites and the five watch lists. Defaults to favourites, preserving explicit device preferences. Original wide rows and sort orders; account-scoped reads and acknowledged history removal |
| Feed | My feed, Fresh, Managed, search | original fourth root-tab slot; period/channel filtering, independent channel/blog/article search envelopes, paginated posts and channel lists. Native article/media/comments/voters/reposts routes; explicit acknowledged channel subscriptions, blog friend requests, votes and hide actions |
| Collections | favourites list, detail | bookmark/unbookmark, paginated releases |
| Comments | list, thread, composer | sorting, spoiler reveal, replies, up/down voting, posting with the spoiler flag |
| Profile | own and others, editor, account health, lists, votes, friends, user search | six privacy-filtered sections, installed nickname badge, grouped friend requests, existing blog/cover reads independent of creation reputation, typed reports and independent full/reply comment sorts |
| Profile badges and themes | previews, categories, detail, code claim, pinned section and badge order | four-column conditional overflow previews, independent pin/selected/rarity markers, theme behind the whole selected section, Lottie JSON for nonzero badge type, owner-only recent object cache with CSV queries; native reorder uses explicit Save/Cancel |
| Schedule | weekly | one request for the week, defaults to today |
| Notifications | feed | episode, friend, related-release and unknown kinds; marks read on open |
| Auth | sign in, register, password reset | email/password; registration and reset both run the emailed-code step |

### Not implemented

| Area | Why |
|---|---|
| Social sign-in (VK, Google, Telegram, Yandex) | needs each provider's SDK and the original app's registered client IDs and redirect URIs, which are not recoverable from the APK in a usable form. The endpoints are in `AuthEndpoints` and `SessionController` already has the methods — only the token acquisition is missing. |
| Article/channel publishing and editing | global/personal feed and existing profile blogs are readable. The native block editor/media-token bridge, post publishing and channel editor remain separate work; managed-channel browsing is not presented as a finished admin editor. |
| Creating and editing collections | needs multipart image upload |
| Broader moderator tooling | typed profile/comment/article/collection report forms and account-health screens exist; broader channel/admin controls are not covered by the profile port |
| Push notifications | `auth/firebase` is wrapped, but APNs needs a server-side counterpart; Anixart's push goes through FCM and AppMetrica |
| Downloads / offline | Android uses `DownloadManager` plus a local Room cache; the port has no persistence layer |
| Torlook torrent search | points at a third-party service configured through `config/toggles` |
| Bookmark import/export | file pickers plus a server-side job (`import/bookmarks`, `export/bookmarks`) |

### Profile verification limits

The 31 Oct–2 Nov 2026 Android audit distinguishes observed screens from static
contracts. Full-list New/Old/Popular ordering was observed; the server's ordering
is preserved without inventing a universal tie-break for equal vote counts.
The filled public-pinned example and concrete animated badge URLs were not
visually confirmed. Synthetic offline fixtures do not close those runtime gaps.

Recent history is only loaded/displayed for the current owner. Successful current
loads refresh cached objects, put the selected badge first and retain at most four;
foreign reads send `recent=""` and do not touch another account's history.
An omitted recent field is not treated as an explicit empty response.

The native Lottie dependency is pinned to 4.5.2 in `project.yml`. Playback pauses
off-screen, outside the active scene, for Reduce Motion and for resource saving.
Models use a bounded count/encoded-JSON cache; raster/GIF avatars are a different
decoder. Native reorder deliberately keeps Save/Cancel instead of Android's
drag/settle auto-save, which can also commit on gesture cancellation.

Both native reorder routes share an account-scoped draft. They reject malformed,
duplicate, over-limit or wrong-owner showcase responses; an acknowledged Save
updates the draft baseline before refreshing the profile, so cancellation of that
read cannot submit the same order twice. Partial pinned/recent objects can fill
missing artwork from the same-ID installed badge or category. The nickname editor
requires successful current reads of both availability and login restrictions;
badge actions stay tied to the viewer/session that loaded their snapshot.

Read-only spot checks on the original phone app confirmed the installed-header
badge detail's "Сменить значок" route into selection, distinct from the selection
detail's "Снять" action, and related-release subtitles in compact tiles. The iOS
header keeps that navigation separate from account writes. No real account was
changed during these checks; a reconstructed design is not used as a reference.

Profile revisions require a fresh macOS build, the offline `AnixartKitTests` and
`AnixartTests` suites, and iOS visual/runtime checks before claiming parity.
OAuth binding and blog/article creation/editing remain unimplemented, not silently
replaced by manual token entry or an account mutation on opening an information page.

### Home/Discover/Release verification limits (2 Nov 2026)

The reference is the original `com.swiftsoft.anixartd` phone app. The coordinator's
read-only text trees confirmed the tab menu/default descriptions, custom and full
filter contexts, franchise search card and distinct related-list route, row actions,
title-copy sheet, two-decimal detail rating, current-release marker and Discover
shortcuts. No reference screenshots were opened by the implementation agent, and
no account/default/filter setting was changed on the reference phone.

Static DEX contracts additionally confirm `API-Version: v2` on release search and
related paging, first-page-only franchise suggestions, the 25-result search page
boundary, banner types (1 release, 2 URL, 3 collection), and video banner actions
(0 category ID from `value`, 1 URL). Generated DTOs were not hand-edited. Video-list
reads are token-free; authenticated reads and writes keep the viewer/session that
opened the screen. Home list writes require an explicit `code: 0`, support removal,
and rebase positional paging after acknowledgement. Random opens detail, not playback.

Earlier alphas stored full-filter fields in the custom-tab preference. Those keys
are still decoded/encoded rather than destructively migrated, but do not become
invisible constraints in the four-field custom form. Genres there use Any matching,
as its observed explanatory text states; the complete catalogue filter retains all
three modes. Opening custom settings selects that tab without changing its launch
default. Applying/resetting settings remains an explicit device-local action.

Offline tests cover stale loads, cancellation, refresh/retry, guest reads and wrong
viewer writes, search paging/suggestions, filters, URL validation and random errors.
Windows tree-sitter checks are syntax checks only. Each revision needs fresh macOS
typechecking/XCTest; navigation, pagination, Dynamic Type and physical-iOS runtime
checks remain distinct from offline model tests and smoke launches. Successful
earlier profile/player CI is not proof for later browsing changes.

The browsing follow-up wires four previously missing routes without reference
images. Voice input uses native Speech/AVFoundation and the two privacy descriptions
in `project.yml`. Only a microphone-button tap or explicit Retry requests permission
or starts audio. Partial text stays in the sheet until a final result or Find; cancel,
manual input, scope/filter changes, account changes, disappearance and inactive
scenes retire the attempt. Recording is bounded to 60 seconds. The audio lease
restores category/mode/options, preserves an existing playback category's activation,
and does not overwrite a newer player configuration. AVAudioSession does not expose
its prior active flag, so this is a documented restoration policy, not proof of
identical playback behaviour on a device. Tests use mocks, never real permissions/audio.

Recommendation help is the APK's native information dialog: `DiscoverFragment`
binds `btn_recommendations_more` to `Ll1Il1I11lI.onClick` case 1, using
`string/information`, `string/no_recommendation_info` and `string/understand`.
Its text is copied verbatim, including the 20 positively rated releases and daily
refresh statement; neither is implemented as a guessed iOS-side eligibility rule.

The original `format_source_link` is `source#<Release.source>`. Its listener sends
event `ll1IIlIl`; `MainActivity.IIl1llI111` opens `ReleaseSearchFragment` with the
source label as `SEARCH_QUERY` and `SEARCH_BY: 5`. This was checked from DEX plus
literal reflection descriptors, not guessed as a web URL or `filter/{page}`.
The iOS link uses that v2 search, keeps the viewer that opened the release, leaves
the ordinary four title-search choices unchanged, and does not touch Home's query
or preferences. Unknown source names remain plain text rather than invented links.

`ReleaseFragment.onScreenshot` passes the source array and tapped index to its
viewer. The iOS full-screen gallery also keeps original order/duplicate URLs,
uses native paging and accessible previous/next/close controls, retries failed
images with fresh cached-loader reads, and retains only the selected frame plus
two neighbours at at most 2048 pixels per longest edge. Inactive scenes release
frame state; viewer changes and closing invalidate callbacks. Reduce Motion uses
a stationary page with the same controls. No gallery image or screenshot was
opened by the implementation agent.

Full Video now reads `video/release/{id}` for `blocks`, `streaming_platforms` and
`last_videos`, then the subsequent token-free `/{page}` requests. Category carousels
link to the original category IDs; their Show all boundary uses the raw 25 count.
Video information reuses the existing detail route; the player itself is unchanged.
Video submission/appeal creation and broader collection/feed editing remain separate.

Native permission prompts, speech availability, audio hand-back, full layouts,
gallery gestures/rotation, Dynamic Type and physical-iOS behaviour remain unverified.
The new offline suites require a fresh macOS build/XCTest; Windows parsing and
Android static/text observations do not establish complete Android/iOS parity.

### Search/bookmarks corrections (2 Nov 2026)

This pass additionally inspected the saved **original Android screenshots**, not
the reconstructed Figma export, and the APK's compiled layouts. `item_search_related`
uses an 86×129 centre poster and two 64×96 side posters; `Related.images` supplies
these, while `Related.image` is the separate 20:9 destination banner. Suggestions
are centred, with the release count and a 200-wide capsule action; neither a row
disclosure chevron nor a small horizontal poster strip replaces that block.

The full filter follows `fragment_filter`: country, category, genres, excluded
lists, voice-over variants, studio, source, paired years/season and episodes/status,
duration, age rating, sort. Choices collapse to outlined fields and Reset/Apply
stay below the scroll. Genre selection retains all three modes and the APK's
labels/hints; the mode and legacy exclusion flag normalize together. Clearing the
last genre removes both keys. Years have a separate Apply/Cancel range editor.
Reset is explicit and keeps the cleared form open. None of this adds filter keys
to a title-search request or alters the Home custom-tab preference.

Both release-search entries request `.navigationBarDrawer(displayMode: .always)`;
the Home/Discover search pill has an explicit capsule hit shape over its entire
padded frame. Bookmarks occupy the third root-tab slot; the subsequent Feed pass
removes the incorrect extra Catalogue tab. The eight inner tabs keep their APK order, scroll to
the selected favourite/default and use an underline, not filled chips. Default
selection is favourites for absent/invalid preferences; a user's explicit choice
is not migrated or overwritten. Wide rows follow the original 104×156 poster,
metadata, excerpt and overflow layout rather than the compact subtitle/status row.

Recent viewing reads the flat episode label or the embedded episode's name/positive
position; it never infers the viewed episode from the release's total count. Its
initial date format was absolute (`d MMM yyyy в HH:mm`) even for today's entries;
the later follow-up below changes profile entries younger than 24 hours to relative
age. Missing metadata is omitted without empty separators or an
invented series. History rows in bookmarks also include the episode and exact time.
Their requests retain the opening viewer, paginate by the APK's raw 25-item rule,
and require an explicit successful deletion before rebasing positional pages.

`ReleaseHistoryContractTests`, `SearchBookmarksPresentationTests` and
`BookmarkReleaseListTests` add offline regressions for these data/default/filter
contracts and stale account/page responses. They do not click a native search
drawer or measure touch coverage. This revision still needs fresh macOS
typechecking/XCTest and iOS checks for repeated search navigation, scrolling,
keyboard dismissal, filter sheets, both themes and Dynamic Type.

### Feed/root-tab correction pass (2 Nov 2026)

The root is exactly Home, Discover, Bookmarks, Feed, Profile. The old diagnostic
`catalog` argument returns Home instead of reviving a sixth/incorrect root screen.
Saved original phone screenshots confirm My feed, Fresh and the Managed icon,
full-width article blocks and separate channel/blog search carousels. Existing
Figma exports predate this pass and must not be used as the current/original UI.

Static APK and live read-only checks distinguish several easily confused contracts:

- Feed My/Fresh posts and article search use the **raw 25** boundary. Subscriptions
  and recommendation lists use **30**; managed channels and channel search use 25.
- `FeedSearchResponse` nests separate `PageableResponse` values in `channels`,
  `blogs`, `articles`, `tags`. Their counts are not interchangeable. Preview groups
  retain page-zero metadata while article paging continues.
- The Feed `date` query is **0 Latest, 1 24 hours, 2 Week, 3 Month, 4 Year, 5 All
  time**, not an epoch timestamp/calendar date. The original switch and resource
  labels were checked directly. It remains independent of release-search filters.
- Managed browsing uses `channel/all` with `ChannelsFilterRequest`, permission=1,
  is_blog=false, sort=1 and optional is_subscribed=true. Channel search uses a
  different request with query and is_blog; neither body is a release search body.
- Anonymous Fresh/latest API reads return code 401, whereas search/feed returns
  the real nested envelopes without a token. Opening Feed shows a sign-in prompt
  instead of silently dispatching authenticated requests or forcing an auth sheet.
- `ArticlePresenterDelegate` sends blog subscriptions to
  `ProfileFriendApi.requestSend(blog_profile_id)`, ordinary subscriptions to
  ChannelApi. The iOS confirmation names the friend-request effect. Removing a
  blog relationship stays in the author's existing explicit profile controls.
- Fresh checks `feed/latest` (`articleId`, camelCase) in a cancellable active-scene
  120-second task. A new-post badge never auto-scrolls/replaces visible posts.

Post/media, channel/profile, comments, voters, reposts and typed article reports
reuse the existing native routes. Mutations require an explicit code=0 and the
opening viewer; missing acknowledgements do not update rows or invent global vote
or subscriber totals. Supplementary article reads have per-ID generations and
read-only retry after an acknowledged vote. Initial paginators display loading,
not a false empty state before their first request/debounce completes.

`FeedContractTests`, `FeedStateTests` and `FeedActionTests` add 33 offline methods
covering wire shape, periods, paging, stale viewers/read responses, root order,
blog-vs-channel actions and acknowledgements. They are not an iOS runtime test.
This pass opened nine screenshots total in the conversation (hard cap 49), made
three anonymous API reads, and did not operate/change the original phone account.
Fresh macOS typechecking/XCTest, physical-iOS navigation/layout checks and the
separate publishing/editing implementation remain required before full parity.

### Appearance/profile refinements (2 Nov 2026)

Device appearance now separates light/dark policy, visual theme and accent.
Original neutral surfaces/lavender and the APK's carmine colour are provided;
OLED forces dark presentation with black base/bar backgrounds while preserving
the user's normal light/dark choice for switching back. Monet-style is an explicit
seed-driven tonal approximation, not a claim to access iOS wallpapers or Android
system Monet colours. Theme-owned UIKit templates use setter-only appearance
proxies and font-only copies; applying either colour or font changes preserves
the other attributes and does not reset root-tab/navigation identity.

The supplied original `dialog_blog_create` layout points to `anixa_wow.webp`. That
unchanged local asset is attributed and bundled for a centred floating upgrade
dialog with current/required reputation, progress, information and the three
original feature descriptions. Opening it does not create a blog, play audio,
publish a post or request permissions. An existing blog remains independent of
creation reputation. `ChannelResponse.CHANNEL_NOT_FOUND=2` is accepted only for
the profile-blog read and treated as normal absence; malformed, wrong-owner,
transport and authentication failures are not silently reclassified as absence.

Reputation shares the presence/registration baseline. Foreign taps show a small
anchored popover identifying that profile's reputation; owner help remains separate.
Friend/contact/menu controls share a row. The contact control exposes published
social links; it is not represented as an implemented Anixart private-chat protocol.
The extra Show lists statistics action is removed while legend/list navigation stays.
Positive donut slices have a bounded minimum visual arc and proportional gaps;
legend counts remain exact and zeros/negative values receive no arc.

Both photo paths use ImageIO originals with ICC/alpha/EXIF retained and explicit
original rendering. No old brightness/saturation filter or proven ICC stripping
was found; tint, transparency and HDR remain possible visual factors. Extended-range
bitmap preservation tests are not a claim to implement HEIF/JPEG gain-map policy.
`AvatarColorTests` adds eight deterministic local methods, the typeface suite sixteen,
and `AppearanceProfileRegressionTests` twelve. The latter includes palette contrast,
OLED, font/colour coexistence, tiny slices, absence handling and mascot bundling.
They require a fresh macOS XCTest run and actual iOS layouts/colour comparisons.
This pass opened four additional reference screenshots: 13/49 conversation reads;
both subagents used code/text only and opened zero screenshots.

### Launch, search, recent viewing and motion follow-up (2 Nov 2026)

`AppEnvironment` owns one `AppLaunchCoordinator`. `AnixartApp` mounts `AppLaunchView`;
the root/screens are not created underneath a loading overlay, so their tasks cannot
race configuration or start a duplicate first-page fetch. Native launch and runtime
loading share the same centred 96-point `LaunchMark` and adaptive neutral background.
The mark is a byte-identical copy of this port's current placeholder app icon, not
new artwork or a claim to use Anixart's original icon. Resource hashing does not
constitute an image-opening or visual validation step.
This icon-led interstitial is the user's chosen presentation, not an Apple HIG
mandate: Launching guidance prefers a launch screen close to the first content
screen and discourages extra branding. Matching native/runtime loading limits the
handoff change but does not make a logo-only loading screen a general HIG rule.

Startup orders remote configuration (4-second deadline), session restoration
(4 seconds), then only the saved Home default tab's first page (12 seconds). These
are maximum stage budgets, not minimum display delays. An unset custom filter has
no warm request; configured-but-unconstrained custom filters are valid. Profile,
release/random-release, player, Kodik and Feed smoke routes skip Home warming.
The completed `ReleaseFeedModel`, including failure state, is available for the
first Home render and handed off once into its state. Tab/filter/viewer mismatches
discard it; the immutable opening viewer prevents later-token borrowing. Existing
`loadFirstPageIfNeeded()` guards do not repeat either success or a retryable failure.
Only the initial warm attempt has the launch deadline; user retry, refresh and
later pages retain normal client timeouts.

The deadline race cancels the losing work without awaiting an uncooperative callback,
so a view waiter's cancellation or slow store cannot trap startup. A still-loading
credential read settles to guest without clearing the store; a cancelled late read
cannot publish an owner under the visible Home feed, and the next cold start can
restore normally. An already restored owner remains signed in when a supplementary
profile/notification read times out. Cancelled configuration neither starts another
config request nor applies late host/toggle changes. Failures expose the normal
content/error/retry UI, not another automatic initial spinner or modal login.
Foreground/resume does not replay startup or reset tab/navigation state. The launch
overlay fades out using the 220 ms motion policy, does not intercept ready-content
input, and disables fading for Reduce Motion, resource saving or Low Power Mode.
No percent progress is fabricated, and launch requests no microphone/permissions.
Full granular cold-start navigation/scroll restoration remains separate work;
opening the saved Home default is not claimed to implement that entire HIG recommendation.

`ReleaseSearchHistoryStore` persists only query/scope/last-use time under
`search.release.history.<profileID>` or `search.release.history.guest`, with a
20-entry bound. Explicit submit, selecting a saved query, opening a title/franchise
result and accepting final/Find voice text record history; debounce/API completion,
partial speech and intermediate typed prefixes do not. Clearing the field does not
clear history. Individual removal is local; the bulk-clear dialog explains that
bookmarks and viewing history are unchanged. Account switches clear a different
owner's active query, while a refreshed session for the same profile can retain it.
All model history commands check the current viewer and matching store owner;
retired callbacks cannot write, remove or clear history. Writes reload preferences
before merging so another search snapshot's queries are not silently overwritten.

`ReleaseHistoryMetadata.viewedAt` uses “только что”, “минуту назад”, “2 мин назад”,
“час назад” and “2 ч назад” for profile views younger than 24 hours. Older entries
retain the exact local date/time, including the year. Small future clock skew up
to 60 seconds is tolerated; genuinely future dates remain absolute. Missing dates
or episode labels are not invented. `RecentViewingMetadata` separates the two
labels with 12-point gaps around the separator and stacks them when width/Dynamic
Type requires it. One minute timeline updates the active visible profile's list;
the same schedule type pauses without replacing its rows/navigation links, and
inactive/hidden views have no repeating schedule. Bookmark-history rows retain
their independent exact-date/time presentation.

The owner's avatar now opens a native SwiftUI `Menu` at the image for Open/Edit/
Delete; opening it performs no account mutation. Deletion still opens the existing
editor's explicit destructive confirmation. Foreign avatar taps remain a direct
gallery route. HIG advises compact layouts to prefer a sheet over a popover; the
earlier forced small reputation popover is an intentional user-requested exception,
not a claim that Apple prescribes that layout.

Motion code review:

| Before | After | Why |
|---|---|---|
| Underlines changed in place without continuity | Matched tab indicators use a 220 ms move curve | Preserve which tab was selected without delaying input |
| A selection animation could propagate into list replacement/loading | List content rejects the selection animation transaction | Avoid whole-list entrances, flashes or staggered result delays |
| Initial/programmatic or keyboard changes could animate the strip | Only touch selection opts in; Return/Space use an animation-disabled transaction | Keep frequent keyboard input and initial positioning immediate |

`AppMotionPolicy` disables custom animations for Reduce Motion or resource saving.
Native navigation/menu transitions remain system-owned; themes, typed search text
and viewing-time refreshes do not acquire a blanket animation. The only new haptic
is a selection cue after acknowledged **local** history removal/clear, not every tap
and not recording speech. No looping decorative animation or artificial delay is
added. Motion purpose/easing/implementation and code review are complete; rapid
retargeting, actual 60-fps behaviour and native keyboard/touch interaction are still
pending iOS runtime validation.

Apple's eight supplied HIG pages were accessible through official DocC JSON; six
are component categories, so recommendations were read from their child articles.
Applicable guidance includes [Menus](https://developer.apple.com/design/human-interface-guidelines/menus),
[Launching](https://developer.apple.com/design/human-interface-guidelines/launching),
[Loading](https://developer.apple.com/design/human-interface-guidelines/loading),
[Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators),
[Searching](https://developer.apple.com/design/human-interface-guidelines/searching),
[Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help),
[Motion](https://developer.apple.com/design/human-interface-guidelines/motion),
[Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
and [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy).
The 24-hour cutoff, storage bound and 220 ms duration are implementation choices,
not HIG mandates. Five root tabs are Anixart's structure, not an Apple requirement.
Newer Liquid Glass and system experiences are not assumed available on iOS 17.

`AppLaunchTests` adds 19 methods; `ReleaseSearchHistoryTests` adds 12 and
`RecentViewingMotionTests` six, for 37 new methods in this follow-up. They cover
startup order, warmed-model handoff, smoke/custom defaults, timeout/retry, stored
and stale viewers, waiter cancellation, late config/credential callbacks, motion
and storyboard layout, plus persistence/scopes, bounds, sparse/malformed data, guest/owner isolation,
retired same/different-account callbacks, multiple snapshots, explicit versus
automatic/voice recording, relative-time boundaries and paused schedules. Older-date
regressions now inject the reference clock. These tests are not executed on
Windows; syntax parsing is not Swift typechecking/XCTest. The conversation remains
at 13/49 screenshot reads; this follow-up and HIG research opened none.

Static validation parses launch asset JSON/XML, verifies native full-view 96-point
centering constraints and the mark's byte equality, and parses 20 literal raw JSON
fixtures. It does not compile the storyboard, run its layout tests or decode Swift
models. The new timetable APIs were checked against Apple's documented iOS 15+
availability; this is not a substitute for compiling against the deployment SDK.
Windows Swift grammar review covers 46 changed files with no grammar findings or
parser-process failures; the two altered session methods also have scoped checks.
The configuration optional binding was separated from its awaited request so the
cancellation boundary is explicit and the parser can handle it. This remains
grammar checking, not Swift typechecking. No fresh macOS build, XCTest or physical-iOS
verification has been performed for these changes, and no new IPA is claimed.

### Smooth interactions, stage 1: selection controls (2 Nov 2026)

`SelectionControls.swift` shares stable-size regular/medium labels, a matched
underline and a travelling selected-chip fill. Home, Bookmarks and Feed reuse the
underline; Profile sections, the All/Dubs/Subtitles selector and hosting chips
reuse the fill. They retain the existing 220 ms move curve, original colours and
native root tab bar. The checkmark has a reserved slot; larger text can scroll
the selectors instead of clipping them. Profile/hosting targets are at least 44 pt.

`SelectionMotionIntent` keeps only a pending input target. Keyboard, default and
unrelated/older selections do not acquire touch motion, and completing an older
target cannot retire a newer one. Repeated selections are ignored; a newer hosting
choice cancels the prior UI-owned selection task. The episode model, request
endpoints and playback flow remain unchanged. Background selection work can finish
after navigation away so returning does not lose an in-flight hosting load.

| Before | After | Why |
|---|---|---|
| Weight/checkmark changes shifted neighbouring labels | Both weights and the optional mark reserve their layout space | Keep the indicator's destination stable during selection |
| Selected chip fills appeared independently | One matched fill travels between stable outlines | Show continuity between the previous and current choice |
| Selection transactions could animate content or permanently suppress its motion | Selection-only content suppression; async hosting motion stays on the strip | Do not animate whole lists or disable future local interactions |

`SelectionMotionTests` adds 11 methods covering input targets, rapid retargeting,
older completions, keyboard, accessibility/resource saving and hosted label sizing
with Dynamic Type/icons/checkmarks. XCTest, Swift typechecking and iOS frame-rate/
touch validation are pending. Windows Tree-sitter reports no grammar findings in
the eight changed Swift files, but its Node process aborts with a memory error on
completion; this is not recorded as a clean validation run. `git diff --check`
reports no whitespace errors in the tracked implementation changes.

### Adaptive profile information and optional existing motion (2 Nov 2026)

`ProfileInfoPresentationPolicy` prefers a sheet for compact/unknown size classes,
landscape and Dynamic Type XX Large or above. Regular layouts with smaller text
keep an anchored popover. The size/font cutoff is an implementation choice, not
an Apple-mandated threshold. A regular popover that becomes compact lets SwiftUI
adapt the same presentation to a sheet; its bounded content can scroll instead
of clipping. Large text/landscape sheets use the large detent, including existing
`ProfileHelpSheet` help. Each presentation has a close control.

Reputation/contact controls share one profile-owned presentation. Source/kind/ID
bindings prevent an older dismissal from closing a later or reopened window.
Viewer changes retire information; avatar gallery/editor commands close it first.
The native avatar Menu and the editor's separate destructive confirmation remain.
Foreign reputation stays a named fact, owner help stays separate, and public
contacts are not represented as an Anixart private-message endpoint.

`AppMotionPolicy.resolvedAnimation` can gate an existing caller-supplied animation
without changing its normal-mode timing. Description expansion, spoiler reveal and
both episode hints retain SwiftUI's prior default animation; Reduce Motion,
resource saving or keyboard activation apply their state immediately instead.
The already-integrated voice-over/source selection uses the same gates. No new
reveal choreography or whole-page/list entrance is introduced in this pass.

`ProfileInfoPresentationTests` adds ten policy/dismissal/owner-reset methods;
`SelectionMotionTests` adds four existing-animation override/state-commit checks.
Local patch whitespace checks pass. Swift typechecking, XCTest and the release
pipeline still require the exact new revision to pass macOS CI. Neither these
offline checks nor alpha publication establish physical-iOS layout, touch or FPS.

### Avatar, sparse statistics and upgrade explanation (2 Nov 2026)

This profile-only follow-up inspected 49 saved original Android PNGs: 25 from
`anixart-profile-reference-20261031` and 24 from `anixart-profile-audit-20261031`.
These are existing dark-theme captures, not new iOS screenshots or 49 distinct
states; a capture's filename alone does not establish what loaded on screen.
No live Android/API writes, new screenshots, CI run or publication were performed.

`ProfileAvatarControl` bounds the native menu source to the 112-point photo;
gallery/edit commands retire identity information, and deletion still requires the
editor's separate confirmation. Preference rows appear independently only when the
server supplies nonblank names, before the watch totals as in filled originals.
Current list counts do not invent or suppress daily server-calculated preferences;
ordinary empty sections, totals and privacy rules remain unchanged. The upgrade
dialog uses more safe-area height and less artwork, keeps all three original feature
descriptions (including the cover), and leaves Close outside the scrollable text.
An explicit iOS publishing limitation avoids implying that reputation unlocks an
unimplemented editor. Large text/short windows can scroll instead of clipping rows.

Eight kit tests and ten app tests cover preference availability/privacy, native
avatar source sizing and adaptive explanation layout. They were added, not executed
on Windows: Swift/Xcode/XCTest and native iOS interaction checks remain unavailable.
The exact revision still needs macOS typechecking/XCTest and iOS visual verification.

## Typography

The Android app styles nearly every text appearance as `sans-serif-medium`, which stock
Android renders in Roboto. The port ships Roboto (Apache-2.0) in
`Anixart/Resources/Fonts/` and defaults to it. Device settings can choose native SF Pro
through `.system`/`UIFont`, without font-file redistribution. `Font.ax(_:_:)` in
`Anixart/Support/Typography.swift` observes the local typeface store, preserves text-style
sizes/Dynamic Type and refreshes existing callers without `.id` replacement. UIKit
navigation/tab font copies preserve theme backgrounds, colours, layouts and selection.

The APK also bundles `product_sans_medium.ttf` for a single style. Product Sans is Google
proprietary and is deliberately **not** shipped here.

## Where the video comes from

**Anixart serves no video.** Measured against the live API in the `probe` job, every hosting it
lists answers with its own player page: Kodik always, Libria's `iframe: false` URL is an HTML
page too, and Sibnet's `shell.php` is a 403. `Episode.iframe` says which shape the API used, not
whether anything is playable — so it must not be used to decide which players to offer. That is
what `StreamProbe` is for: it fetches the first kilobyte and looks for `ftyp` or `#EXTM3U`.

**So the stream comes from the hosting's own API.** Anixart's Libria URL,
`anixart.libria.fun/public/iframe.php?id=9307&ep=1`, carries AniLibria's own release id — 9307 is
the release AniLibria returns for "Киберпанк: Бегущие по краю", 1210 for "Ванпанчмен". So
`anime/releases/{id}` gives that episode's `hls_480`, `hls_720` and `hls_1080` directly, each a
real playlist. No title matching and no scraping of anyone's player.

`AnixartKit/Streams` holds that layer: `StreamSource`, `StreamOffer` and `StreamResolver`, with
`AniLibriaStreamSource` as the only source so far. The app resolves an episode to a
`PlaybackTarget` (`Anixart/Features/Player/PlaybackTarget.swift`) before the player appears:
Anixart's own URL when it really is a stream, otherwise a source's, otherwise nothing and only
the web player is offered.

**The gap is Kodik, and it is most of the catalogue.** Measured in the `probe` job: «Киберпанк:
Бегущие по краю» lists 25 voice-overs, and the hostings are `{Kodik: 25, Libria: 1, Sibnet: 1}`;
«Ванпанчмен» lists 19, `{Kodik: 17, Libria: 1, Sibnet: 1, Sovet: 2}`. So a voice-over almost
always lives on Kodik alone, and a source like AniLibria supplies its *own* dub rather than
unlocking anyone else's — it cannot stand in for a Kodik entry.

**How the original plays Kodik, which this port must copy.** An earlier version of this file
claimed the APK's Kodik parser "runs its strings through a decryption routine" and called that
circumventing the hosting's protection. That was wrong twice over, and the correction matters:

* The decryption is **LSParanoid** (`org.lsposed.lsparanoid`), the string obfuscator this APK
  applies to *every* literal in *every* class — the API paths this port already uses were
  obfuscated the same way. It has nothing to do with Kodik.
* `KodikParser` itself fetches the public player page and pulls four quality URLs out of it with
  four regexes, prefixing `https:` on a protocol-relative one and rewriting the host with two
  string replaces. Ordinary reading of a public page.

**The Kodik path, from the live `config/toggles`.** Everything it needs is server-side, and the
model for it (`TogglesResponse`) was generated from the APK at the start of this port — but
`loadRemoteConfiguration()` only fetched `config/urls`, so these were always nil, and
`versionCode` was 1050 instead of the manifest's 26101718, which is the field the server gates on.
With both fixed:

    kodikAdIframeUrl   = "https://anixmirai.com/iframe/ad?url="
    kodikIframeAd      = true
    kodikVideoLinksUrl = "https://kodikplayer.com/get-video-info"
    iframeEmbedUrl     = "https://anixmirai.com/iframe?url="
    staticDomain       = "anixmirai.com"
    sibnetUserAgent    = "Mozilla/5.0 (Linux; Android 10; MAR-LX1M) … Chrome/86 …"
    sibnetRandUserAgent = true
    lastVersionCode    = 26101718
    impMessageText     = "Сейчас наблюдаются временные проблемы с работой видео из источника
                          Kodik на территории РФ."

So the wrapper is on `anixmirai.com`, not `anixart-app.com` where twelve guessed paths all
returned the same catch-all. `KodikWrapper` builds
`kodikAdIframeUrl + urlencode(scheme://host/path) + "&v=" + versionCode`, which is what
`KodikAdActivity` loads, and the web player now goes through it too — a hosting's page is not
meant to be opened directly. `sibnetUserAgent` explains Sibnet's 403: the server tells the client
which agent to present. And that `impMessageText` is Anixart's own notice that Kodik video is
currently broken in Russia, which is worth reading before blaming this port for a dead stream.

**What a Kodik page actually does**, measured from a WKWebView in the simulator
(`-anixart-screen kodik`, or Настройки → Диагностика on a device):

    3 frames: kodikplayer.com/seria/<id>/<hash>/720p, about:blank, ls.kodikres.com/storage.html
    xhr   cloud.solodcdn.com/test/<32 hex>:<YYYYMMDDHH>/g?_=<ms>
    load  kodikplayer.com/assets/js/app.player_single.<hash>.js
    load  ls.kodikres.com/local-storage.min.js
    fetch mc.yandex.ru/watch   (site-info carries "domain":"anixart-app.com")
    fetch mc.yandex.ru/clmap   (pointer-click — the synthetic tap registers)
    advert finished: no       media URLs: 0

So the page loads in full, performs one dated CDN reachability check against
`cloud.solodcdn.com`, and stops. No `/ftor`, no manifest, no media. Together with
`advert finished: no` that says the stream is only requested *after* the advert
has run — which is exactly the order `KodikAdActivity` implies, since it waits
for `advertEnded` before playing anything. The advert is AdSense, and it does not
serve a simulator on a datacentre address, so this is as far as CI can measure:
the rest needs a real device.

And `KodikAdActivity` shows what the flow really is. It loads Kodik's page in a WebView, taps the
centre once on `onPageFinished` (autoplay needs a gesture), and registers a JavaScript bridge as
**`KodikInterface`** — which Kodik's own player then calls back as `advertEnded()`. Kodik built
support for this. The app watches the hosting's ad as the hosting intends, and only then plays the
episode in the chosen player. So the iOS port is a `WKWebView` with a `WKScriptMessageHandler`
shimmed as `window.KodikInterface.advertEnded`, and `probe-kodik-page.py` measures the page so the
extraction is written against what is actually served.

One route remains closed:

* ShikiApp, suggested as a place to take sources from, does not contain any. Its binary holds no
  provider hostnames at all: it embeds the whole of `yggdrasil-go` (plus gvisor's netstack and a
  SOCKS/CONNECT proxy), carries the string `at least one yggdrasil peer is required`, and its
  only ATS exception is a single Yggdrasil address, `201:601c:…`, over plain HTTP. Its
  `KodikParser`, `CollapsParser`, `AksorParser` and `CvhParser` run against whatever that overlay
  peer serves. Those sources are a service someone runs, not code that can be lifted, and
  pointing this app at it would be using a third party's private infrastructure.

Services that publish their own dubs through a public API are the remaining avenue. AniLibria is
one and is implemented.

**AnimeLib is not.** `api.lib.social` answers where `api.cdnlibs.org` returns a Cloudflare page,
and it names its teams per episode and carries the Shikimori id itself, so it needs no bridge.
But measured over four titles that matched -- «Ванпанчмен» (14 players), «Стальной алхимик:
Братство» (5), «Клинок, рассекающий демонов» (11), and «Магическая битва» (no match at all) --
*every* player is `player: "Kodik"` with an empty `video.quality`. AnimeLib embeds Kodik rather
than hosting the video, so it is the same wall one step further out.

**Shikimori** answered the runner with HTTP 522 on every attempt. It is only needed as a bridge
for a source that identifies titles by Shikimori id; nothing currently does.

Dressing a request up as a browser to get past a Cloudflare 403 would be the same circumvention
as the Kodik parser, so the probes record a refusal and stop there.

**RuTube works as a bridge but has nothing to offer.** Anixart's RuTube URL does carry RuTube's
own video id — `f2910dcbe135717a6f5e90141592bb22`, the right shape — and
`rutube.ru/api/play/options/{id}` answers with JSON, so the mechanism is the same one-request
bridge the Libria URL gives. The one sample available comes back
`{"detail": {"type": "blocking_rule", … "Видео недоступно по решению п…"}}` under HTTP 244: the
API is working and saying that video is blocked. And RuTube is rare — absent from twelve random
releases, one voice-over out of «Магической битвы»'s thirty. A source worth perhaps one
voice-over per title where it appears, whose only observed video is blocked, is not worth the
code; the probe keeps asking, so if that changes it will show up in the job summary.

`Источник 1`, listed once by «Клинок», has not been looked at yet.

**Quality comes from the source, not a fixed list.** A source that publishes one playlist per
quality decides the rungs, so "Ванпанчмен" offers 480p and 720p and no 1080p. Switching replaces
the player item and carries the position over; there is no bitrate ladder inside these playlists
to cap. AniLibria's URLs carry `isWithVideoAds=1`, so its own ad segments are part of the stream.

**The web player is still the fragile part.** Kodik, Sibnet and VK Video check `Referer` and user
agent before handing out a stream. `EmbedPlayerView` sends the same `Referer` the Android app uses
(`https://anixart-app.com`) and a desktop user agent, and blocks link navigation so a tap cannot
bounce the user to a store page. These pages change their anti-embedding behaviour without notice;
expect this file to need maintenance. The Android app also carries an adblock list
(`assets/adblock.txt`) that is not ported.

### «Режим улучшения видео +»

The APK runs an Anime4K-derived GLSL shader as an ExoPlayer effect. Here the same kernel is a
Core Image kernel (`Anixart/Resources/Shaders/VideoEnhance.ci.metal`) over frames pulled off the
player with `AVPlayerItemVideoOutput` — a video composition cannot touch an HLS stream, and HLS is
all the built-in player ever gets.

Several things in it are deliberately *not* the APK's:

* The APK's gradient is `(r - l, l + 2c + r)`. The second term is a sum, not a derivative, so it
  reads 91% vertical on a vertical edge and exactly vertical on a flat patch — it was blending
  every pixel with the one below it. Replaced with a real 3×3 Sobel, and the result is clamped to
  the neighbourhood's own min/max, which is what a halo cannot survive.
* Sharpening is luma-only. Per-channel sharpening moves the hue at an edge, which on flat anime
  fills shows up as a coloured rim.
* The gradient is Scharr, not Sobel. Sobel under-reads a 45° edge by about a tenth relative to a
  vertical one, and anime is diagonals — a jawline, an eyelash, a strand of hair. That bias was
  landing on exactly the lines worth keeping.
* The restore pass runs twice at 60% strength rather than once at full. One large step overshoots
  on anything that is not a clean straight edge, which is most of a face; two small steps converge
  on the same line, and the second aims better because the first cleaned up the gradients it reads.
* `flat_relief` takes the quantisation terraces out of smooth shading. A 480p stream spends almost
  no bits on a cheek or a sky, so they arrive as visible steps — and sharpening makes those steps
  crisper, which is why more sharpening never made a face look better. Where the detector sees no
  real edge this averages the neighbourhood instead (on a smooth ramp the mean *is* the centre, so
  genuine shading survives; on a one-code step the step is what disappears) and adds sub-visible
  noise to break the quantisation that formed the band. It runs on the decoded frame only.
* The chain is restore → Lanczos upscale → restore, as Anime4K's own is. 480p and 720p are most of
  what the hostings serve, so the frame is stretched roughly 2× on the way to a phone screen;
  everything the first pass recovers at the decoded grid is resampled soft again, and only a
  second pass at the display's grid puts the edge back. The second pass runs at 60% strength,
  because it is working on interpolated pixels — there is no detail there to recover, only an edge
  to keep.

### Anime4K proper

The APK ships a *simplified* Anime4K — a hand-written edge detector and sharpener. Upstream
Anime4K is something else: trained convolutions baked into shaders. `ThirdParty/Anime4K` vendors
the two small ones (MIT licensed, verbatim, never hand-edited — they are weights):

* `Anime4K_Restore_CNN_S` — four 3×3 layers with a residual connection, fitted to undo the blur
  and compression a low-bitrate encode leaves behind.
* `Anime4K_Upscale_CNN_x2_S` — four more plus a depth-to-space layer that doubles the picture.

They are written for mpv's shader-hook format, so `Tools/convert-anime4k.py` translates them into
Core Image Metal kernels: one function per pass, plus a Swift description of the wiring
(`Anime4KChain.swift`). Re-run it after updating the vendored files; never edit the output.

The one real difference is coordinates. mpv hands each pass normalised texture coordinates; Core
Image hands it a destination pixel and a `transform` into each sampler's space, and a pass whose
output is twice its input's size cannot get that mapping out of Core Image, because both images
sit in one working space at different scales. So every position is computed from `dest.coord()`
and sizes passed in as arguments, and nothing is inferred.

Two runtime details are load-bearing. The context runs with `workingColorSpace: NSNull()`, because
both kernels want the frame's own gamma-encoded values — the hand-written one because its
thresholds were tuned on them, Anime4K because that is what mpv gives its hooks. And the working
format is `RGBAh`: the convolutions' intermediate layers carry negative numbers and numbers above
one, and an 8-bit intermediate clipping them does not look like an artefact, it looks like the
network failed.

Cost, measured off the shaders rather than guessed: one pass is nine samples and nine 4×4 matrix
multiplies, about 144 MACs per pixel. `Restore_CNN_S` is roughly 600 MACs per pixel, so about
0.55 GMAC per 720p frame — around 66 GFLOPS at 60fps, which a phone GPU has several times over.
The M, L, VL, UL and GAN variants (up to 300 KB of weights) are sized for a desktop GPU driving a
4K display and are deliberately not vendored.

The three-way dial (Слабо / Средне / Сильно) scales the deblur and sharpening amounts only.
Средне is the APK's own numbers. The edge threshold and the anti-ringing clamp are never scaled:
those are what keep it from breaking.

## Known risks

**`NSAllowsArbitraryLoadsInWebContent` is on.** Some hostings still serve player assets over
plain HTTP. It is scoped to web content only — the API itself is HTTPS.

**No local cache.** Every screen fetches on appearance. The Android app has a Room cache; adding
one here would mean a second model layer, since the DTOs are deliberately all-optional. Images are
the exception: `Anixart/Support/ImageLoader.swift` keeps decoded posters in memory and their bytes
in a `URLCache` on disk, downsamples to the size actually drawn, and falls back to
`mirror-static.anixart.tv` when the primary host does not answer.

**`versionCode` is hardcoded** in `AnixartEnvironment`, at `26101718` — the manifest's value for
10.5, confirmed against the live `lastVersionCode`. `config/toggles` and `config/urls` both
receive it, the Kodik wrapper URL carries it, and the server gates features and forced updates on
it, so bump it when tracking a newer Android release. It was `1050` for most of this port — a
number derived from the version *name*, which meant the client announced itself as years out of
date on every launch.

**The config responses decode leniently, everything else does not.** `config/toggles` sends
`"searchBarIconTint": "false"` — a string among two dozen real booleans. Jackson coerces that
silently, so the Android app never noticed; Swift's synthesised `init(from:)` threw, and one
mistyped flag cost the *whole* response, including `kodikAdIframeUrl`, `kodikVideoLinksUrl` and
`kodikIframeAd`. The player kept opening Kodik's page directly and getting «данной страницы не
существует». `TogglesResponse` and `ConfigUrlsResponse` are now generated with a decoder built on
`Networking/LooseScalars.swift`, which coerces scalars; the catalogue models are left strict, so a
real shape change there still fails loudly. Both are fetched and decoded by the `probe` job now,
which is the check that was missing.

**Inferred enum values.** Season order and comment sort values were read off the UI rather than
from a constant. They are commented as inferred in the Swift source; if sorting looks wrong,
check these first.

## Regenerating the models

The generated types come from the APK, not from hand-editing:

```bash
# model_map.json was produced from a jadx decompilation of the APK:
python3 Tools/extract-models.py <jadx-out>/sources/com/swiftsoft/anixartd > Tools/anixart-10.5-model-map.json
python3 Tools/generate-models.py Tools/anixart-10.5-model-map.json \
    Packages/AnixartKit/Sources/AnixartKit/Models/Generated
```

`generate-models.py` holds the decisions that cannot be derived mechanically: the `RENAME`
table (Swift has its own `Collection` and `Type`), `DROP` (back-references that would make a
Swift value type recursively contain itself, plus Room-only fields), and `TYPE_OVERRIDE`.
