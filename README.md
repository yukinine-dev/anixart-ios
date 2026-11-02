# Anixart for iOS

A native iOS client for Anixart, ported from the Android app (`com.swiftsoft.anixartd` 10.5).
SwiftUI, iOS 17+, async/await. The core has no third-party dependencies;
the app uses native [Lottie](https://github.com/airbnb/lottie-ios) (Apache-2.0)
for animated profile badges.

This is an unofficial client. It talks to the same public API the Android app uses and adds
nothing that bypasses it — no ad removal, no premium unlocking, no scraping around the API.

---

## What is and is not verified

CI builds and runs this on macOS. Successful runs verify:

- **It compiles.** `AnixartKit` and the iOS app target both build, and the kit's
  **unit tests pass**.
- **It launches.** A simulator boots the app, and the job fails if a crash report
  appears or the process is gone 25 seconds later. It survives.
- **It decodes live API responses.** The probe and launch/profile/release smoke
  routes read configuration and public catalogue, profile and release content.
  The smoke job fails on an app decoder error. This checks the reverse-engineered
  JSON keys against real server payloads, not only against offline fixtures; it
  does not establish that every navigation route or hosting works.

What that does **not** cover:

- **Only the launch, public-profile and release-detail smoke routes are exercised.**
  Catalogue, filter, search, the episode drill-down, bookmarks and comments compile and
  are wired to APK-verified endpoints, but are not clicked through in the simulator. Owner-only profile
  flows have offline regression tests, not an end-to-end simulator account check.
- **Playback is untested.** Both players are the least certain part of the port — see
  "Known risks" in `docs/PORTING.md`.
- **It has never run on a physical device**, only in the simulator.

CI results apply only to the exact tested revision. Badge previews, recent history,
ordering and Lottie have offline fixtures; those do not establish full live parity.
Syntax checking on Windows is not Swift typechecking or XCTest.

The 2 Nov 2026 Home/Discover audit used text UI trees from the original Android
application, not the reconstructed design. It adds offline regressions for
viewer-scoped feeds/actions, release-search paging and franchise navigation,
banner/video-category contracts and random-release failures. Each revision requires
a fresh macOS build and test run; an earlier alpha's green CI does not verify later
changes. Android observations are not iOS runtime or full-parity checks.

Browsing follow-up adds native, explicitly started speech input, the APK's
recommendation information dialog, full-screen screenshot paging and the
source-material search link (`searchBy: 5`), plus the full video hub's category and
streaming blocks. Permission/audio and gallery lifecycle regressions use injected
mocks, never a real microphone. Native permission dialogs, speech availability,
audio restoration and gallery gestures still need iOS runtime verification.

The search/bookmarks follow-up uses saved screenshots and compiled layouts from
the original Android app: an always-visible native search field, full-pill hit
area, centred franchise suggestion, outlined full-filter controls and original
wide bookmark rows. Bookmarks occupy the third slot and default to Favourites
unless explicitly configured otherwise. Recent viewing shows the embedded episode
when the flat label is absent. Profile views from the last 24 hours show a short
relative age; older views and bookmark-history rows retain the exact local
date/time. Added offline regressions still require a fresh macOS build/XCTest run;
Windows syntax checks do not verify these layouts or touch behaviour on iOS.

The root tabs are **Главная / Обзор / Закладки / Лента / Профиль**. There is no
separate Catalogue tab. Feed browsing now has My feed, Fresh and Managed sections,
period/channel filters, paged channel/blog/article search and native post/media,
comment, voter and repost routes. Fresh/personal feeds require login (confirmed by
anonymous API `code: 401`); feed search is public. Blog subscription uses the APK's
friend-request route with an explicit explanation, not a channel-subscribe write.
Publishing/editing posts and channels remains unimplemented. The added feed tests
and Windows syntax checks still need a fresh macOS build and iOS runtime checks.

Appearance/profile refinements add original neutral/lavender and carmine-accent
themes, true-black OLED and a seed-driven **Monet-style** palette (not iOS wallpaper
access), plus a live device-local **Roboto / native SF Pro** choice. Reputation
and presence share a row; foreign reputation shows a profile-specific fact rather
than the owner's help text. Reputation/contact information uses a sheet for compact
layouts and large Dynamic Type, and an anchored popover in regular space. Tiny
nonzero chart slices remain visible, and the
profile's absent-blog API code is not presented as a failed login/load. The
upgrade information dialog uses the original local Anixa artwork without creating
a blog. Photo decoders retain ICC/alpha and explicitly render originals; no
brightness filter is used or claimed as a proven fix for every image. These later
edits require a new build/XCTest and iOS visual check, not Build 95's earlier result.

Cold start now shows the same static app mark in the native launch screen and the
runtime loading view. Configuration/session restoration precede warming the saved
Home tab's first page; Home adopts that complete model instead of requesting it
again. Errors/timeouts reveal normal retry UI. Unset custom filters and non-Home
smoke routes skip irrelevant warm requests, and foreground/resume never restarts
the coordinator. This is a new flow, not a verified physical-device launch result.

Home search now has a device-local, account/guest-separated history of at most 20
queries, recorded only on submit, history selection, opening a result or accepting
voice input. Entries can be removed and clearing requires confirmation; intermediate
typed prefixes, API results and tokens are not stored. Avatar commands use a native
menu at the photo, with deletion still separately confirmed. Episode/view-age labels
have independent spacing and a vertical fallback for large text. Tab indicators
move briefly (220 ms), without animating the result list; Reduce Motion, resource
saving and keyboard activation disable custom movement. These changes still need
fresh macOS typechecking/XCTest and native-iOS interaction checks.

Profile information has explicit close controls, scrollable content and a single
identity presentation per profile. Avatar editing/gallery routes close that
information first; the native avatar menu and separate deletion confirmation stay.
Existing description, spoiler and episode-hint animations retain their original
normal-mode timing but now obey Reduce Motion, resource saving and keyboard input.
This does not add new reveal effects or establish physical-device smoothness.

Alongside the run, these were checked mechanically:

- all 92 endpoint paths were diffed against the 296 Retrofit annotations extracted
  from the APK — they match exactly;
- the JSON key for every model field came from the APK's Jackson `@JsonProperty`
  annotations rather than hand-typing, via a committed script that reproduces both the
  extracted map and all 60 generated Swift files (`Tools/`);
- the unit tests assert the wire shape directly: token as a query parameter, form
  encoding, the filter body's snake_case keys with absent rather than null fields,
  `searchBy` staying camelCase, mirror-host rewriting, and the mixed-casing payloads.

The `smoke` job also prints the first frame into its log as a base64 JPEG, so the
rendered screen can be inspected without downloading the artifact.

## Releases

Every push to the development branch that gets past the simulator launch test is
published as an **alpha pre-release** on the
[Releases page](https://github.com/yukinine-dev/anixart-ios/releases), with the `.ipa`
attached. They are tagged `v0.1.0-alpha.<build>` and marked as pre-releases, which
keeps the repository's "Latest release" empty — an alpha is never presented as the
finished thing.

When the port is ready to be called finished, run the **Build** workflow manually
(Actions → Build → Run workflow) with **"Publish as a full release"** ticked. That
publishes `v<MARKETING_VERSION>` as a normal release instead. Bump
`MARKETING_VERSION` in `project.yml` first.

The same `.ipa` is also attached to each run as the `Anixart-unsigned-ipa` artifact,
which is the quicker route while iterating.

## Installing the IPA

No Apple Developer certificate exists in this repository, so builds have code signing
switched off and **iOS will not install the `.ipa` as-is** — it has to be re-signed
with a certificate you control.

The usual routes, in order of how long the install lasts:

| Tool | Needs | Install lasts |
|---|---|---|
| [Sideloadly](https://sideloadly.io) | any Apple ID | 7 days on a free account, a year on a paid one |
| [AltStore](https://altstore.io) / SideStore | any Apple ID | same, but refreshes itself |
| [TrollStore](https://github.com/opa334/TrollStore) | a device and iOS version it supports | permanent |
| Xcode | the repo and a Mac | 7 days, or a year on a paid account |

A free Apple ID also caps you at three sideloaded apps. The bundle identifier is
`app.anixart.client`; change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` if it collides
with something you already have installed.

**To get a directly installable build instead**, add an Apple Developer signing certificate
(`.p12`) and a provisioning profile to the repository's Actions secrets and switch the `ipa`
job to a signed `xcodebuild archive` / `-exportArchive`. Nothing in the port needs to change
for that — only the signing settings, which are deliberately empty here.

## Layout

```
Packages/AnixartKit/          platform-agnostic core — no SwiftUI, unit-testable on its own
  Models/Generated/           60 Codable types generated from the APK's @JsonProperty data
  Models/                     enums, request bodies, display helpers, polymorphic notifications
  Networking/                 AnixartClient (actor), Endpoint, errors, keychain token store
  API/                        typed endpoints grouped by area
Anixart/                      the iOS app
  App/                        entry point, DI container, session, root tabs
  Features/                   one folder per screen area
  Components/                 posters, cards, paginated list, status views
  Support/                    Paginator, formatters, theme
Tools/                        the extraction/generation scripts and the extracted model map
docs/API.md                   the reverse-engineered API reference (300 endpoints)
docs/PORTING.md               Android → iOS mapping, feature coverage, known gaps
```

## What the API looks like

Three things shape the whole client and are worth knowing before reading the code:

1. **The session token is a query parameter**, not a header: `?token=...`.
2. **Failure arrives as HTTP 200** with a non-zero `code` in the body, so `AnixartClient`
   checks every decoded response and raises `AnixartError.api`.
3. **The host is not fixed.** `config/urls` returns the live API host list and a
   `shouldUseMirrorUrls` flag; the client adopts both at launch, including the `mirror-`
   host rewriting the Android app does.

`docs/API.md` has the rest, including why the JSON key casing is mixed and which enum values
are confirmed versus inferred.

## Feature coverage

Implemented: the icon-based cold-start flow, local Home query history, the Главная
tabs (four-field Моя вкладка plus the eight catalogue presets),
explicit device-local default-tab selection, discover feed and its five browsing shortcuts,
the full filter and paginated release search with franchise results, release detail,
explicit native voice search, full-screen screenshots, source-material search,
the video hub and categories, voice-over/source/episode drill-down, playback (native and embedded), watch lists, favourites,
history, collections, comments, profiles, friends, schedule, notifications, email sign-in and
registration. Profiles include the six privacy-filtered sections, editor/account-health flows,
badge categories and pin markers, whole-section themes, native JSON badge animations and
explicit Save/Cancel ordering. Recent badge history is account-scoped and sent as CSV.
The Feed tab includes personal/fresh posts, managed-channel browsing, channel/blog
search and scoped subscription/voting/hide actions; no post is published on opening it.

Not implemented: social sign-in/binding (needs the VK/Google/Telegram/Yandex SDKs and registered
iOS client IDs), collection, article and channel creation/editing,
broader moderator tooling, push notifications, downloads and the Torlook torrent search.
Existing profile blogs and typed report forms are implemented. `docs/PORTING.md` has the
full matrix and the remaining verification limits.

## Licence and attribution

Anixart, its API, its content and its branding belong to their owners. The original
Anixa mascot used by the upgrade dialog is attributed in
`Anixart/Resources/Images/ATTRIBUTION.md`; the port does not claim ownership. Its app
icon remains a placeholder. This client is not affiliated with or endorsed by the
Anixart team. SF Pro is used through Apple's system font API, not redistributed files.
