import Foundation

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
    /// The press was a tap. Recording continues while we wait to see whether a
    /// second tap follows; the caller must arm a timer for
    /// `DictationShortcutSessionController.doubleTapWindow` and then call
    /// `handleDoubleTapWindowExpiration(timestamp:)`.
    case awaitSecondTap
    /// A lone tap: discard the recording without transcribing it.
    case cancel
}

/// Drives one dictation session from shortcut events.
///
/// One binding, two gestures:
///
/// - **Hold** — press and keep holding to record, release to stop.
/// - **Double tap** — two quick taps start a hands-free recording that keeps
///   running until a single tap stops it.
///
/// A press always starts recording immediately, so the beginning of a phrase is
/// never clipped while we wait to learn which gesture it was. Released after
/// `tapThreshold` it was a hold and recording stops. Released within
/// `tapThreshold` it was a tap, and recording keeps running for up to
/// `doubleTapWindow` while we wait for a second tap: if one arrives the session
/// latches, and if none does the recording is cancelled rather than transcribed,
/// since a lone tap captures nothing worth sending.
final class DictationShortcutSessionController {
    /// Longest press that counts as a tap rather than a hold.
    static let tapThreshold: TimeInterval = 0.25

    /// Longest gap between a tap's release and the next press for the two to
    /// count as a double tap.
    static let doubleTapWindow: TimeInterval = 0.3

    private(set) var activeMode: RecordingTriggerMode?
    private(set) var toggleStopArmed = false
    /// Timestamp of the press, so its release can be classified as a tap or a
    /// hold.
    private(set) var holdActivatedAt: TimeInterval?
    /// Timestamp of a tap's release while waiting to see whether a second tap
    /// follows. Non-nil only during that window.
    private(set) var awaitingSecondTapSince: TimeInterval?

    /// - Parameter timestamp: monotonic time of the event. Injected so the
    ///   gesture classification is deterministic under test.
    func handle(
        event: ShortcutEvent,
        isTranscribing: Bool,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> DictationShortcutAction? {
        // Paste Again is handled before this controller runs; if it ever
        // reaches here, treat as a no-op so dictation state is unaffected.
        if event == .copyAgainTriggered || event == .addVocabularyTriggered { return nil }

        guard let mode = activeMode else {
            guard !isTranscribing, event == .holdActivated else { return nil }
            activeMode = .hold
            toggleStopArmed = false
            awaitingSecondTapSince = nil
            holdActivatedAt = timestamp
            return .start(.hold)
        }

        switch mode {
        case .hold:
            switch event {
            case .holdActivated:
                guard let awaitingSecondTapSince else { return nil }
                if timestamp - awaitingSecondTapSince < Self.doubleTapWindow {
                    // Second tap: latch. The stop press is armed by this
                    // press's own release, not by this press.
                    self.awaitingSecondTapSince = nil
                    holdActivatedAt = nil
                    activeMode = .toggle
                    toggleStopArmed = false
                    return .switchedToToggle
                }
                // Too late to pair. Expiration should already have cancelled
                // this session; if its timer is merely running late, treat the
                // press as a fresh first press over the recording still in
                // flight rather than dropping the input.
                self.awaitingSecondTapSince = nil
                holdActivatedAt = timestamp
                return nil

            case .holdDeactivated:
                // Ignore the release of a press we are no longer tracking.
                guard awaitingSecondTapSince == nil else { return nil }
                if releaseIsTap(at: timestamp) {
                    holdActivatedAt = nil
                    awaitingSecondTapSince = timestamp
                    return .awaitSecondTap
                }
                reset()
                return .stop

            case .copyAgainTriggered, .addVocabularyTriggered:
                return nil
            }

        case .toggle:
            switch event {
            case .holdActivated:
                // A latched session stops on the binding's next press.
                guard toggleStopArmed else { return nil }
                reset()
                return .stop
            case .holdDeactivated:
                // Arms the press that follows: the second tap's release, or a
                // release after `forceToggleMode()` latched while still down.
                toggleStopArmed = true
                return nil
            case .copyAgainTriggered, .addVocabularyTriggered:
                return nil
            }
        }
    }

    /// Called when the double-tap window elapses. Returns `.cancel` when no
    /// second tap arrived, and nil when the window is no longer open — the
    /// session latched, stopped, or restarted in the meantime.
    func handleDoubleTapWindowExpiration(
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> DictationShortcutAction? {
        guard let awaitingSecondTapSince,
              timestamp - awaitingSecondTapSince >= Self.doubleTapWindow else {
            return nil
        }
        reset()
        return .cancel
    }

    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        toggleStopArmed = false
        holdActivatedAt = nil
        awaitingSecondTapSince = nil
    }

    func forceToggleMode() {
        activeMode = .toggle
        toggleStopArmed = false
        holdActivatedAt = nil
        awaitingSecondTapSince = nil
    }

    func reset() {
        activeMode = nil
        toggleStopArmed = false
        holdActivatedAt = nil
        awaitingSecondTapSince = nil
    }

    private func releaseIsTap(at timestamp: TimeInterval) -> Bool {
        guard let holdActivatedAt else { return false }
        return timestamp - holdActivatedAt < Self.tapThreshold
    }
}
