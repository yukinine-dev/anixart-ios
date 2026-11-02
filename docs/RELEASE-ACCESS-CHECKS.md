# Release access regression checks

`ReleaseAccessPolicyTests` covers the local first-use age acknowledgement and
the release's server-supplied playback restriction flags. Acknowledgement does
not grant a server permission and never removes a region/view/deletion block.

Native iOS checks required after a fresh macOS build:

- With no saved `release.adultAcknowledged.v1`, open an adult release. Its poster
  and description must remain hidden behind the age confirmation sheet.
- Back out without confirming, then open another adult release: confirmation
  must still be required. Swiping the sheet away must not reveal the content.
- Confirm using **Да, мне есть 18**. Subsequent adult releases on this device
  should not ask again until sign-out. Non-adult releases should never show the sheet.
- Tap **Воспроизвести** on a region-restricted release. Show the licensing
  explanation (including the server's note), not the episode picker. Deleted and view-disabled releases must
  remain unavailable.
- Change the viewer while the playback destination or restriction alert is
  open. No old-viewer playback presentation should be retained.
- Repeat with large Dynamic Type, landscape, Reduce Motion and resource saving.
- Verify that the bundled warning animation renders; backgrounding and closing
  the sheet must stop its loop. Confirming must not restart animation elsewhere.

The original warning uses `age_rating == 5` (release wire values are 1-based,
unlike filter picker indexes), not `is_adult`. Its artwork is the APK's unmodified
`res/raw/sticker_4.json`, a 3-second 60-fps Lottie animation, not a GIF. SHA-256:
`662f469ca40a5b8bc7e0944504498a10f8177ce8bb06d6a5501b5206baaea6ff`.
The loop pauses off-screen, in background, under Reduce Motion or resource saving.
Licensing text is not invented from a restriction flag: it must come from `note`.

Windows syntax parsing is not Swift typechecking, XCTest, a simulator launch,
or proof of any of these native interactions. Archived Android screenshots are
reference material, not screenshots of the changed iOS application.

## Detail and franchise follow-up

- Studio/author/director fact rows now have separate aligned icons and scoped
  search links. The original ReleaseSearchFragment uses studio `1`, director `2`,
  author `3`, source `5`. Earlier `SearchScope` title-language names remain
  compatibility aliases for stored numeric values; the visible labels are corrected.
- **На главный экран** selects the root Home tab and resets its navigation stack,
  rather than pushing another HomeView into release navigation. This is in-app
  navigation, not installation of an iOS Home Screen shortcut.
- Franchise rows have square season/type badges and an accent-coloured connector
  behind the posters. First/last endpoints stop at poster centres.
- Franchise description **Подробнее** is based on measured truncation, not an
  arbitrary character count. Short descriptions must not show a no-op button.
- Three implementation directions reviewed 49 existing Android PNGs each. The
  release direction's selected images mostly cover other screens and contain no
  franchise screen; they do not prove franchise visual parity or the Mushoku
  Tensei runtime case. Check that case on iOS after a fresh macOS build.
