# FreeFlow fork — remove mandatory screen recording

Personal fork. Goal: keep Fn-key push-to-talk dictation, remove the Screen
Recording permission requirement and all screenshot capture.

Upstream: https://github.com/zachlatta/freeflow (MIT, Zach Latta)
Target: macOS, Apple Silicon, Xcode.

---

## Setup

```bash
git clone https://github.com/zachlatta/freeflow.git
cd freeflow
git checkout -b no-screenshot
```

Open in Xcode. **Before writing any code**, set a fixed bundle identifier and
a stable signing identity — otherwise macOS revokes the Accessibility
permission on every rebuild and the paste injection silently stops working.
This costs an evening if skipped.

---

## Prompt for Claude Code

```
This is a personal fork of FreeFlow, a macOS dictation app in Swift.

GOAL
Remove the mandatory Screen Recording permission and all screenshot capture,
while preserving app-context awareness through Accessibility APIs only
(bundle id, app name, focused window title, selected text). Those require
no screen recording permission.

Everything else must keep working unchanged: Fn-key push-to-talk, hotkeys,
vocabulary, transcription, post-processing, overlay.

CHANGE 1 — Setup wizard (Sources/SetupView.swift)
- In `private enum SetupStep: Int, CaseIterable` (line ~58), remove
  `case screenRecording`. The enum is Int-backed and CaseIterable, so verify
  no code depends on specific raw values after removal; renumber if needed.
- In `canContinueFromCurrentStep` (line ~1090), remove the
  `case .screenRecording: return appState.hasScreenRecordingPermission` branch.
- Remove the corresponding step view and any `startScreenRecordingPolling`
  call or timer tied to it.

CHANGE 2 — Context collection (Sources/AppContextService.swift)
- `collectContext()` (line ~94) must no longer call
  `captureActiveWindowScreenshot`. Keep `focusedWindowTitle`,
  `selectedText`, and the app identity fields.
- Delete `captureActiveWindowScreenshot` (line ~421) and `captureWindowImage`
  (line ~564), plus the `CandidateWindow` helper struct and any now-unused
  bounds helpers.
- Remove the `import ScreenCaptureKit` and all CGWindowList* calls.
- The `AppContext` struct (line ~12) likely has a screenshot/dataURL field.
  Remove it and fix every construction site.

CHANGE 3 — LLM payload
- Find where the context is sent to the LLM as an image content block
  (`["type": "image_url", ...]`). Remove that block. Keep the text context.
- Adjust the accompanying prompt so it no longer refers to a screenshot.

CHANGE 4 — Remove the hard failure
- Find the error path producing "A screenshot is required for context-aware
  transcription. Recording has been stopped." and delete it. Recording must
  never be blocked by context collection.
- Search for `hasScreenRecordingPermission` across the whole project and
  remove remaining references, including any AppState property, polling
  timer, and Info.plist usage description key for screen recording.

CONSTRAINTS
- Do not touch GlobalShortcutBackend.swift, ModifierKeyEventState.swift,
  HotkeyManager.swift, or ShortcutCore/. The Fn key handling is correct and
  fragile — leave it alone.
- Do not refactor beyond the scope above.
- After each change, build and confirm it compiles before moving on.

VERIFY
Build and run. Confirm: setup wizard completes without asking for Screen
Recording; the app never appears under System Settings > Privacy & Security >
Screen Recording; dictation works end to end.
```

---

## Verification (do this yourself, not via the agent)

```bash
# 1. No capture APIs left anywhere
grep -rn "ScreenCaptureKit\|CGWindowListCreateImage\|CGWindowListCopyWindowInfo\|SCShareableContent" Sources/
# expected: no output

# 2. No screenshot reaching the network layer
grep -rn "image_url\|dataURL\|jpeg\|JPEG" Sources/
# expected: no output

# 3. Endpoints unchanged
grep -rhoE "https?://[a-zA-Z0-9./_-]+" Sources/ | sort -u
# expected: api.groq.com, api.github.com only
```

Then the real test: run the app, dictate once, and check that FreeFlow is
absent from System Settings → Privacy & Security → Screen Recording.

---

## After it works

Order of value, each independent:

**1. Cleanup prompt.** `Sources/PostProcessingService.swift` holds the LLM
formatting layer. Replace its prompt with `cleanup-prompt.md` (FR/EN
code-switching, LIGHT/FULL modes, app-aware formatting). Highest quality
gain for the least work.

**2. Vocabulary.** `Sources/AppState+AddVocabularyButton.swift` already
implements custom vocabulary. Seed it with: n8n, Sidekiq, ActiveRecord,
Hotwire, Kamal, Scalingo, plus client and repo names. Cheapest accuracy win
available.

**3. Language.** Confirm the Groq transcription call passes `language: "fr"`
explicitly and hits the `/audio/transcriptions` endpoint, never
`/audio/translations`. Model should be `whisper-large-v3`, not turbo.

**4. Local ASR (optional, later).** Swap Groq for WhisperKit
(https://github.com/argmaxinc/WhisperKit) via SPM to go fully offline.
Real work, not a config change — only worth it if the privacy or offline
requirement becomes real.

---

## Known pitfalls

**Accessibility permission resets on rebuild.** The permission is bound to
the (bundle id + signature) pair. Ad-hoc signing produces a new signature
each build, macOS revokes the grant, and Cmd+V injection silently no-ops.
You will debug correct code. Fix it upfront:

```bash
security find-identity -v -p codesigning

codesign --force --deep --sign "YOUR_IDENTITY" \
  --identifier com.appvise.freeflow /Applications/FreeFlow.app
```

Always build to the same path with the same identifier.

**The enum is Int-backed.** `SetupStep: Int, CaseIterable` — removing a case
shifts every subsequent raw value. If anything persists the step index to
UserDefaults, users resume mid-wizard at the wrong step. Check before
removing.

**Do not touch the Fn code.** `ModifierKeyEventState.swift` contains a
non-obvious fix: Fn state from `flagsChanged` events is unreliable, so it
tracks a trusted state separately. That comment is someone's lost afternoon.
Leave it.
