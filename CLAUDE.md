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

Done — CHANGE 1: `screenRecording` step removed from the setup wizard.
Remaining — CHANGE 2 (`Sources/AppContextService.swift`), CHANGE 3 (LLM
payload), CHANGE 4 (remove hard failure). Details in `freeflow-fork-brief.md`,
along with follow-up improvements.

## Do not modify

- `Sources/GlobalShortcutBackend.swift`
- `Sources/ModifierKeyEventState.swift`
- `Sources/HotkeyManager.swift`
- `Sources/ShortcutCore/`

The event tap and Fn key detection are correct and fragile.
`ModifierKeyEventState.swift` contains a non-obvious fix: Fn state from
`flagsChanged` events is unreliable, so a trusted state is tracked separately.
Do not refactor it.

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
