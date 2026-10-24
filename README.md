# Anixart for iOS

A native iOS client for Anixart, ported from the Android app (`com.swiftsoft.anixartd` 10.5).
SwiftUI, iOS 17+, async/await, no third-party dependencies.

This is an unofficial client. It talks to the same public API the Android app uses and adds
nothing that bypasses it — no ad removal, no premium unlocking, no scraping around the API.

---

## Read this first

**The Swift in this repository has never been through a compiler.** It was written in a Linux
container with no Swift toolchain and no network access to the API host, so neither the build
nor a single live request could be checked here. What *was* verified:

- all 92 endpoint paths in `AnixartKit` were diffed against the 296 Retrofit annotations
  extracted from the APK — they match exactly;
- the JSON key for every model field was taken mechanically from the APK's Jackson
  `@JsonProperty` annotations, not hand-typed (`Tools/extract-models.py`,
  `Tools/generate-models.py`);
- the model graph was checked for Swift-illegal recursive value types and unresolved type
  references;
- every endpoint and type the app layer references was checked to exist.

Expect to spend a session fixing compiler diagnostics before it runs. `.github/workflows/ios.yml`
builds the app and runs the `AnixartKit` tests on macOS, so **the first CI run is the real
first compile** — start there rather than guessing.

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
