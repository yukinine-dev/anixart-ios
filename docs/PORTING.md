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
| Главная | tab strip, nine tabs | Моя вкладка (device-local filter, with its full settings screen) plus the eight presets, each mapped to the exact `filter/{page}` query `HomeFragment` sends; long-press sets the default tab |
| Discover | обзор feed | banners, discussing, continue watching, recommendations, comments of the week; blocks load concurrently and a failed block is omitted rather than taking the screen down |
| Catalogue | browse, filter, search | full `FilterRequest`: sort, category, status, season, years, episode count, age rating, genres with all three match modes, voice-over, "hide what's already in my lists" |
| Release | detail, titles, videos, streaming platforms, collections | poster over its own blurred backdrop, the list/bookmark/comments row, Воспроизвести with the last added episode under it, the icon fact lines, genre links, description with Подробнее, Видео banners, rating histogram with star voting, В списках у людей, Кадры, Связанные релизы, the collection links, Рекомендуем также and the comment preview |
| Playback | "Выберите вариант", episode list, player | the voice-over list with the Все/Озвучки/Субтитры filter, episode and view counts, and the СУБТИТРЫ and НОВИНКА badges; then the hosting picker and episodes. `AVPlayer` for direct URLs, `WKWebView` for `iframe` episodes; watched marks, resume, progress reporting |
| Bookmarks | 8 tabs | collections, history, favourites and the five watch lists, with the sort order the Android app offers |
| Collections | favourites list, detail | bookmark/unbookmark, paginated releases |
| Comments | list, thread, composer | sorting, spoiler reveal, replies, up/down voting, posting with the spoiler flag |
| Profile | own and others, lists, votes, friends, user search | the Android layout: avatar with the online dot, login with the sponsor crown, status, rating score, join date, the action row, the friends row, and the Статистика / Оценки релизов / Коллекции chips over the watch-list legend and donut |
| Schedule | weekly | one request for the week, defaults to today |
| Notifications | feed | episode, friend, related-release and unknown kinds; marks read on open |
| Auth | sign in, register, password reset | email/password; registration and reset both run the emailed-code step |

### Not implemented

| Area | Why |
|---|---|
| Social sign-in (VK, Google, Telegram, Yandex) | needs each provider's SDK and the original app's registered client IDs and redirect URIs, which are not recoverable from the APK in a usable form. The endpoints are in `AuthEndpoints` and `SessionController` already has the methods — only the token acquisition is missing. |
| Articles and channels (the social feed) | the largest remaining area: ~20 screens, a block-based article editor, reposts, suggestions, channel moderation. `Article` and `Channel` models exist; `ArticlePayload` is a sealed block hierarchy that was not modelled. |
| Creating and editing collections | needs multipart image upload |
| Reports and moderation | `report/*` exists in the API reference; no UI |
| Profile themes, badge showcases, achievements | cosmetic systems with a lot of surface (`Badge`, `BadgeAward`, `BadgeCategory` are modelled; the showcase endpoints are not wrapped) |
| Push notifications | `auth/firebase` is wrapped, but APNs needs a server-side counterpart; Anixart's push goes through FCM and AppMetrica |
| Downloads / offline | Android uses `DownloadManager` plus a local Room cache; the port has no persistence layer |
| Torlook torrent search | points at a third-party service configured through `config/toggles` |
| Bookmark import/export | file pickers plus a server-side job (`import/bookmarks`, `export/bookmarks`) |

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

**The gap is titles AniLibria does not carry.** A Kodik-only release still has no stream, so the
built-in player is not offered for it and the picker says why. Closing that means another
source, and the APK's own Kodik parser runs its strings through a decryption routine —
circumventing that hosting's deliberate access protection, which is a different thing from using
Anixart's open API, and is deliberately **not** ported.

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

## Known risks

**`NSAllowsArbitraryLoadsInWebContent` is on.** Some hostings still serve player assets over
plain HTTP. It is scoped to web content only — the API itself is HTTPS.

**No local cache.** Every screen fetches on appearance. The Android app has a Room cache; adding
one here would mean a second model layer, since the DTOs are deliberately all-optional. Images are
the exception: `Anixart/Support/ImageLoader.swift` keeps decoded posters in memory and their bytes
in a `URLCache` on disk, downsamples to the size actually drawn, and falls back to
`mirror-static.anixart.tv` when the primary host does not answer.

**`versionCode` is hardcoded to 1050** in `AnixartEnvironment`, matching the Android build this
was read from. `config/toggles` and `config/urls` both receive it, and the server uses it to
gate features and force updates — bump it when tracking a newer Android release.

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
