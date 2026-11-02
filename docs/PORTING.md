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
| Catalogue | browse, full filter, search, native voice input | full `FilterRequest`: sort, country, studio, source material, category, status, season, years, episode count/duration, age rating, genres with all three match modes, voice-over, excluded account lists. Release search pages by the APK's raw 25-item rule, preserves page-zero franchise metadata and exposes same-page retry. Voice input is explicit, permission-aware and scoped to the current query/viewer/scene |
| Release | detail, titles, video hub/categories, streaming platforms, collections | poster over its own blurred backdrop, the list/bookmark/comments row, Воспроизвести with the last added episode under it, the icon fact lines, genre and source-material search links, description with Подробнее, Видео banners and full hub, rating histogram with star voting, В списках у людей, full-screen Кадры, Связанные релизы, the collection links, Рекомендуем также and the comment preview |
| Playback | "Выберите вариант", episode list, player | the voice-over list with the Все/Озвучки/Субтитры filter, episode and view counts, and the СУБТИТРЫ and НОВИНКА badges; then the hosting picker and episodes. `AVPlayer` for direct URLs, `WKWebView` for `iframe` episodes; watched marks, resume, progress reporting |
| Bookmarks | 8 tabs | collections, history, favourites and the five watch lists, with the sort order the Android app offers |
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
| Global articles/channels feed and publishing | existing profile blogs, article blocks, galleries, comments, voters and repost lists are readable. The block editor/media-token bridge, publishing flow and global feed remain separate work. |
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

## Typography

The Android app styles nearly every text appearance as `sans-serif-medium`, which stock
Android renders in Roboto. The port therefore ships Roboto (Apache-2.0) in
`Anixart/Resources/Fonts/` and routes every `.font(...)` through `Font.ax(_:_:)` in
`Anixart/Support/Typography.swift`, which keeps Apple's text-style sizes and `relativeTo:`
so Dynamic Type still works. The navigation and tab bars are UIKit-drawn and do not see
SwiftUI's font modifiers, so they are set through the appearance proxies in `AppFont`.

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
