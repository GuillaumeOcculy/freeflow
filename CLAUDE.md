# FreeFlow — Claude Code guide

Native macOS menu-bar dictation app built directly with `swiftc` and Make. No
Swift Package Manager, no Xcode project. Preserve that architecture.

`AGENTS.md` holds the full upstream maintenance guide (repository map, privacy
rules, definition of done, code review rules). Read it before non-trivial work;
this file only adds fork-specific context and overrides.

## Fork context

Personal fork of zachlatta/freeflow (MIT). Personal use only, never
redistributed. No notarization, no App Store, no multi-platform support.

Goal: remove the mandatory Screen Recording permission and all screenshot
capture, while keeping app-context awareness via Accessibility APIs only
(bundle id, app name, focused window title, selected text).

Because nothing ships, the upstream rules about releases, notarization, version
bumps, branches and pull requests do not apply — commit to `main` directly.

## Status

Screenshot removal (see `freeflow-fork-brief.md`) — **done**, CHANGE 1 to 4.
Verified by hand: FreeFlow no longer appears under System Settings > Privacy &
Security > Screen Recording, and dictation works end to end.

App context now comes from Accessibility APIs only: app name, bundle id,
focused window title, selected text. Nothing captures, sends or stores an
image, and context collection can no longer block a recording — including in
Edit Mode, which used to refuse to start without the permission.

Notes for anyone re-reading the brief:

- CHANGE 2 and 3 landed as one commit. The `image_url` block lives in the same
  file as the capture, so removing `AppContext`'s screenshot fields forces the
  payload change; splitting them would not have compiled.
- The brief underestimated the reach. The screenshot was also persisted in
  `PipelineHistoryItem` and its Core Data entity, and rendered in the debug
  panel and the test-case export. All of that is gone; lightweight migration
  handles the dropped columns.
- Removing the `SCShareableContent` call is what actually delists the app.
  It never captured anything — it existed only to register FreeFlow in the
  Screen Recording list.

Remaining from the brief: the four "After it works" improvements — cleanup
prompt, vocabulary seeding, `language: "fr"` check, optional local WhisperKit.
One caveat found while reading it: the cleanup prompt's rule "convert spoken
numbers to digits above ten, keep small numbers as words" would undo the
current behavior of writing dictated "1, 2, 3" as digits. Adjust that line
before applying the prompt.

Dictation shortcut (outside the brief, done):

- The separate Hold to Talk and Tap to Toggle bindings were merged into one
  "Dictation Shortcut". Holding records and releasing stops; double-tapping
  records hands-free until a single tap stops it. A lone tap is cancelled
  rather than transcribed.
- Timing lives in `DictationShortcutSessionController`: `tapThreshold`
  (250 ms) separates a tap from a hold, `doubleTapWindow` (300 ms) is the gap
  allowed between the two taps. Both are tuned by feel.
- The controller stays clock-free so it remains testable without sleeps. The
  double-tap timer belongs to `AppState` and `SetupTestHotkeyHarness`, which
  call `handleDoubleTapWindowExpiration(timestamp:)` when it fires.

## Do not modify

- `Sources/GlobalShortcutBackend.swift`
- `Sources/ModifierKeyEventState.swift`
- `Sources/HotkeyManager.swift`

The event tap and Fn key detection are correct and fragile.
`ModifierKeyEventState.swift` contains a non-obvious fix: Fn state from
`flagsChanged` events is unreliable, so a trusted state is tracked separately.
Do not refactor it.

`Sources/ShortcutCore/` is *not* protected: it holds the shortcut models, the
matcher and the session state machine, and it is where dictation behavior is
meant to change. Keep it free of AppKit and of wall-clock reads so the tests
stay deterministic — take timestamps as parameters and leave timers to callers.

## User context

French developer. Dictation is ~95% French with embedded English technical
terms (merge, staging, webhook, deploy, commit). Those must never be francized
in transcription or post-processing output. See `cleanup-prompt.md` for the
post-processing prompt design.

## Build

```bash
make          # build build/FreeFlow Dev.app
make run      # build and launch
make check    # typecheck + tests + plist/shell/YAML validation — must pass before every commit
git diff --check
```

`make check` runs a full Swift type-check with `-warnings-as-errors`, compiles
and runs the deterministic tests, and lints plists, shell scripts and YAML.

Codesign identity is a self-signed certificate named "FreeFlow Dev";
`CODESIGN_IDENTITY` in the Makefile depends on it. The identity plus the fixed
bundle id keep the Accessibility grant alive across rebuilds — change either and
macOS silently revokes it, breaking paste injection.

Production sources are discovered automatically by the Makefile. Test
dependencies must be listed explicitly in `TEST_PRODUCTION_SOURCES`.

## Working rule

One change at a time: implement, run `make check`, test manually, commit.
`make check` proves it compiles, not that it works — manual testing is required
before each commit. Anything touching microphone capture, global shortcuts,
Accessibility, clipboard or paste behavior cannot be verified by tests alone.

## Privacy

Never commit, print or fixture: API keys, real audio or transcripts, selected
text or clipboard contents, window titles, or pipeline-history exports from a
real session. Use synthetic data in tests. See `AGENTS.md` for the full list.
