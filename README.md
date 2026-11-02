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
  API/                        92 typed endpoints grouped by area
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

Implemented: the Главная tabs (four-field Моя вкладка plus the eight catalogue presets),
explicit device-local default-tab selection, discover feed and its five browsing shortcuts,
catalogue with the full filter, paginated release search with franchise results, release detail,
explicit native voice search, full-screen screenshots, source-material search,
the video hub and categories, voice-over/source/episode drill-down, playback (native and embedded), watch lists, favourites,
history, collections, comments, profiles, friends, schedule, notifications, email sign-in and
registration. Profiles include the six privacy-filtered sections, editor/account-health flows,
badge categories and pin markers, whole-section themes, native JSON badge animations and
explicit Save/Cancel ordering. Recent badge history is account-scoped and sent as CSV.

Not implemented: social sign-in/binding (needs the VK/Google/Telegram/Yandex SDKs and registered
iOS client IDs), the global articles/channels feed, collection and article editing,
broader moderator tooling, push notifications, downloads and the Torlook torrent search.
Existing profile blogs and typed report forms are implemented. `docs/PORTING.md` has the
full matrix and the remaining verification limits.

## Licence and attribution

Anixart, its API, its content and its branding belong to their owners. This port carries no
Anixart assets — the app icon and accent colour are placeholders. It exists as a client for an
API that is already public, and it is not affiliated with or endorsed by the Anixart team.
