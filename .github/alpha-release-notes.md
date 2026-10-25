Build `__BUILD__` from `__SHA__`.

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

CI compiled it, ran the AnixartKit unit tests, booted a simulator, launched the app and
confirmed the process survives with no crash report. It then relaunches the app straight
onto a profile and onto a release page and photographs both, so those two screens are
checked to render against live data with no decode failures.

Everything else — catalogue, search, the episode drill-down, bookmarks and comments — is
built and wired to verified endpoints but is not clicked through. **Playback is not
tested at all.** This has only ever run in a simulator, never on a physical device.

See [`docs/PORTING.md`](../blob/__SHA__/docs/PORTING.md) for what is not implemented yet.
