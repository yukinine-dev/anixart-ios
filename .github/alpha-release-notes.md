Build `__BUILD__` from `__SHA__`.

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

Player XCTest covers native AVPlayer failure and recovery using a local PCM WAV file,
resume position, speed, quality, stale callbacks, stop and web-fallback routing. Live
player screenshots and hosting diagnostics are best-effort: the full Kodik
advert-to-video transition is not a required passing test.

Everything else — catalogue, search, the episode drill-down, bookmarks and comments — is
built and wired to verified endpoints but is not clicked through. This has only ever
run in a simulator, never on a physical device.

See [`docs/PORTING.md`](../blob/__SHA__/docs/PORTING.md) for what is not implemented yet.
