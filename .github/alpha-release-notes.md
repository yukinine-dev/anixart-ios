Build `__BUILD__` from `__SHA__`.

## Home, search and release updates

- Tab settings include an explicit launch-default selector and separate four-field settings for the device-local custom tab.
- Release search uses the original v2 contract, paginated results, a separate franchise card and same-page retry. The full filter is accessible from search; Apply switches to filter results even when its values are unchanged. Old queries and sessions cannot replace current results.
- The full catalogue filter includes studio, source material and episode duration. Empty selections are omitted, and guest browsing does not borrow account-list exclusions.
- Known 25-item browsing feeds use raw page sizes instead of stopping at a misleading zero or last-index page count.
- Discover has Popular, Schedule, Collections, Filter and Random shortcuts, current-session loading and partial-refresh retry. Discussion rows show daily rather than lifetime comment counts.
- Release details copy only real titles, retain two-decimal ratings and distinguish franchise headers from related-release lists.
- Home and filtered-result menus offer favourites and viewing status. Selecting the current status is a no-op; acknowledged changes rebase the displayed feed, and failed aggregate refreshes do not undo successful writes.
- Video banners use their action/category IDs, and invalid URLs cannot open an empty web player. Random opens a release detail, not playback.

## Profile updates

- Badge previews use four columns, conditional overflow and independent pin/selection markers; partial entries retain their artwork.
- The installed nickname badge opens its details; "Change badge" opens the selection screen without changing the account. Compact tiles retain related-release subtitles.
- Animated badges use native Lottie, paused off-screen, in the background, for Reduce Motion and for resource saving.
- Recent badges are cached per account and sent as CSV; foreign profile reads do not borrow that history.
- Badge changes require a current owner snapshot and explicit server acknowledgement, including after signing in again to the same account.
- Both reorder screens use an explicit Save/Cancel draft; cancelled refreshes cannot submit an acknowledged order twice.
- Nickname editing waits for both availability and restrictions, with retry after a failed load.

## Before you install

This `.ipa` is **unsigned** — no Apple Developer certificate exists in this repository,
so iOS will not install it as-is. Re-sign it with one you control:

| Tool | Needs | Install lasts |
|---|---|---|
| [Sideloadly](https://sideloadly.io) | any Apple ID | 7 days free, a year on a paid account |
| [AltStore](https://altstore.io) / SideStore | any Apple ID | same, refreshes itself |
| [TrollStore](https://github.com/opa334/TrollStore) | a supported iOS version | permanent |

Bundle id is `app.anixart.client`. A free Apple ID caps you at three sideloaded apps.

## What this build is checked against

CI compiled it, ran the AnixartKit and app XCTest suites, booted a simulator, launched the app and
confirmed the process survives with no crash report. It then relaunches the app straight
onto a profile and onto a release page and photographs both, so those two screens are
checked to render against live data with no decode failures.

Profile regression tests use isolated fixtures for artwork, recent history, ownership,
ordering, cancellation and nickname availability. Read-only Android checks use the
original phone app, not a reconstructed design. This does not establish full runtime
parity on a physical iOS device; live public-pinned and animated badge examples remain
verification gaps in `docs/PORTING.md`.

Browsing regressions also cover query/session isolation, raw-count pagination,
franchise suggestions, filters, acknowledged row actions, URL validation and random
failures. Public read-only API checks confirmed the v2 franchise response and the
pagination metadata differences; those HTTP observations are not iOS UI tests.

Player XCTest covers native AVPlayer failure and recovery using a local PCM WAV file,
resume position, speed, quality, stale callbacks, stop and web-fallback routing. Live
player screenshots and hosting diagnostics are best-effort: the full Kodik
advert-to-video transition is not a required passing test.

Catalogue, search, filter dialogs, the episode drill-down, bookmarks and comments are
built and have offline regressions where noted, but are not clicked through in the
simulator. Voice input, recommendation help, the full screenshot gallery and source
information links are not completed by this browsing patch. This has only ever run
in a simulator, never on a physical iOS device.

See [`docs/PORTING.md`](../blob/__SHA__/docs/PORTING.md) for what is not implemented yet.
