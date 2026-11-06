# Player release checks

## Support policy proposal

Keep the existing iOS 17.0 deployment target for now. A deployment target is
not evidence that every supported device/OS combination works. Do not raise it
just because development is tested on a recent Pro Max.

Before claiming broad support, test these coverage roles (some devices may
cover multiple roles):

| Role | Required evidence |
|---|---|
| Oldest supported iPhone tier, running the minimum OS | Native playback and web fallback on physical hardware; enhancement optional and measured separately |
| Compact SE-class screen | Player controls, keyboard/composer, title page, bookmarks and profile remain usable without clipped actions |
| Mid-range non-Pro iPhone | Sustained playback, memory pressure, buffering, resume and enhancement performance |
| Modern ProMotion iPhone | Frame pacing, quality changes, rotation, PiP and newest user-tested OS |
| iPad | Rotation, safe areas, presentation and control layout; the current project targets both iPhone and iPad |

Use simulators for functional/layout regressions and older OS coverage when a
runtime is available. Do not use simulator results as GPU, heat or battery evidence.
The current CI selects an available iPhone simulator, not an OS/device matrix.
Its Xcode 26 SDK selection does not establish coverage of a newer OS.

Record the exact commit, device, OS, source/hosting, stream resolution/frame
rate, selected enhancement mode, playback speed, power mode and test duration.
Do not record session tokens or signed stream URLs in public reports.

## This patch: avoid duplicate enhancement submissions

Previously, the renderer retained the last decoded buffer for pause/resize,
but ran its Core Image/Metal processing again on every display tick even when
that buffer and the output configuration were unchanged.

The patch keeps the buffer and display polling, but only submits processing for:

- a newly decoded frame, including the first frame when enabled while paused;
- a changed drawable size, fit/fill choice or enhancement strength;
- presentation invalidation after drawable resize or app activation.

A frame remains pending if a drawable/command buffer cannot be obtained.
Item attachment and teardown reset submission bookkeeping.

This is not adaptive quality, source-frame-rate scheduling, thermal management,
HDR/color work or a new upscaler. It does not stop the MTKView display timer,
change shader weights, reduce the source frame rate or promise battery savings.
Actual rendering and performance still require iOS runtime verification.

## Automated checks to run on macOS

Generate the project with `xcodegen generate`, then run the existing Anixart
scheme's tests on an available iPhone simulator:

```sh
xcodebuild test \
  -project Anixart.xcodeproj \
  -scheme Anixart \
  -destination 'platform=iOS Simulator,id=<AVAILABLE_SIMULATOR_UDID>' \
  -only-testing:AnixartTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

`EnhancedFrameRenderStateTests` tests submission decisions only. It does not
exercise AVPlayerItemVideoOutput, Metal, UIKit notification delivery, PiP or
real display retention. The existing workflow runs the full AnixartTests target.

## Manual regression checklist

- [ ] Enable every available enhancement mode during playback and while paused.
- [ ] After one paused frame settles, verify with Metal System Trace/GPU capture
      that unchanged display ticks do not submit this enhancement pipeline.
- [ ] Compare a fixed local 24/30/60 fps clip against the same baseline commit.
      Do not infer repeat submissions solely from visual similarity.
- [ ] On pause, keep the enhanced frame visible; resume without black/frozen frames.
- [ ] Seek while paused, including a seek that decodes a new frame.
- [ ] While paused, change fit/fill, strength and orientation; redraw correctly once.
- [ ] Switch quality while playing and paused; do not retain the old episode/frame.
- [ ] Simulate buffering and retry; a newly available frame must still render.
- [ ] Background/foreground while paused, while playing and with PiP; preserve
      video/audio behavior and re-present a paused frame on activation.
- [ ] Toggle enhancement repeatedly and close/reopen the player; check observer
      cleanup, memory and output attachment.
- [ ] Compare baseline/enhanced sustained playback (for example, 20 minutes per
      mode) on the lower and middle device tiers; record frame drops, memory,
      thermal state and energy usage without inventing acceptance numbers.
- [ ] Repeat functional checks under Low Power Mode and thermal pressure.

Before merging, require fresh app build/XCTest results and a physical-device
pass for this patch's pause, seek, geometry, quality and activation scenarios.
No such result is claimed by preparation of this patch.
