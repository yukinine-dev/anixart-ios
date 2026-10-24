# Anixart for iOS

A native iOS client for Anixart, ported from the Android app (`com.swiftsoft.anixartd` 10.5).
SwiftUI, iOS 17+, async/await, no third-party dependencies.

This is an unofficial client. It talks to the same public API the Android app uses and adds
nothing that bypasses it — no ad removal, no premium unlocking, no scraping around the API.

---

## What is and is not verified

CI builds this on macOS, and it is green: `AnixartKit` compiles and its **19 unit tests
pass**, and the **iOS app target compiles** for the simulator on both arm64 and x86_64.
That is a real compile of every file here, not a claim.

What has *not* happened: **no request has ever been made to the live API**, and the app has
**never been run** on a simulator or a device. The container this was written in has no Swift
toolchain and no network route to the API host, so everything beyond "it compiles and the unit
tests pass" is untested — runtime behaviour, layout, and playback above all.

Alongside the compile, these were checked mechanically:

- all 92 endpoint paths in `AnixartKit` were diffed against the 296 Retrofit annotations
  extracted from the APK — they match exactly;
- the JSON key for every model field was taken from the APK's Jackson `@JsonProperty`
  annotations rather than hand-typed, by a committed script that reproduces both the
  extracted map and all 60 generated Swift files (`Tools/`);
- the unit tests assert the wire shape directly: token as a query parameter, form encoding,
  the filter body's snake_case keys with absent rather than null fields, `searchBy` staying
  camelCase, mirror-host rewriting, and decoding of the mixed-casing payloads.

So the first thing to do is run it against the real API and see what the server actually
returns.

## Getting started

```bash
brew install xcodegen
./Scripts/bootstrap.sh          # generates Anixart.xcodeproj and opens it
```

The Xcode project is generated from [`project.yml`](project.yml) rather than committed, so the
project file cannot silently drift from the source tree.

To run the core tests without Xcode:

```bash
cd Packages/AnixartKit && swift test
```

## Installing the IPA

CI builds an **unsigned** `.ipa` on every push and uploads it as the
`Anixart-unsigned-ipa` artifact (Actions → the run → Artifacts). No Apple Developer
certificate exists in this repository, so the build has code signing switched off and
**iOS will not install it as-is** — it has to be re-signed with a certificate you control.

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

Implemented: discover feed, catalogue with the full filter, search, release detail,
voice-over/source/episode drill-down, playback (native and embedded), watch lists, favourites,
history, collections, comments, profiles, friends, schedule, notifications, email sign-in and
registration.

Not implemented: social sign-in (needs the VK/Google/Telegram/Yandex SDKs and the original
app's client IDs), the articles and channels social feed, collection and article editing,
moderation and reports, profile themes and badge showcases, push notifications, downloads,
and the Torlook torrent search. `docs/PORTING.md` has the full matrix and the reasoning.

## Licence and attribution

Anixart, its API, its content and its branding belong to their owners. This port carries no
Anixart assets — the app icon and accent colour are placeholders. It exists as a client for an
API that is already public, and it is not affiliated with or endorsed by the Anixart team.
