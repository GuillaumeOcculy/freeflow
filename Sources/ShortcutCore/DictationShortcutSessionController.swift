import Foundation

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
}

/// Drives one dictation session from shortcut events.
///
/// There is a single dictation binding and it is unified: a press always
/// starts recording, and the release decides what the press meant. Released
/// within `tapThreshold` it was a tap, so recording continues and latches into
/// toggle mode until the next press. Released later it was a hold, so
/// recording stops on release.
final class DictationShortcutSessionController {
    /// Longest press of the dictation binding that counts as a tap rather
    /// than a hold.
    static let tapThreshold: TimeInterval = 0.25

    private(set) var activeMode: RecordingTriggerMode?
    private(set) var toggleStopArmed = false
    /// Timestamp of the binding's press, so its release can be classified as
    /// a tap or a hold.
    private(set) var holdActivatedAt: TimeInterval?

    /// - Parameter timestamp: monotonic time of the event. Injected so the
    ///   tap/hold classification is deterministic under test.
    func handle(
        event: ShortcutEvent,
        isTranscribing: Bool,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> DictationShortcutAction? {
        // Paste Again is handled before this controller runs; if it ever
        // reaches here, treat as a no-op so dictation state is unaffected.
        if event == .copyAgainTriggered { return nil }

        guard let mode = activeMode else {
            guard !isTranscribing, event == .holdActivated else { return nil }
            // Start held; the release decides tap versus hold.
            activeMode = .hold
            toggleStopArmed = false
            holdActivatedAt = timestamp
            return .start(.hold)
        }

        switch mode {
        case .hold:
            switch event {
            case .holdDeactivated:
                if releaseIsTap(at: timestamp) {
                    // Tap: keep recording and latch into toggle. The key is
                    // already up, so the next press stops.
                    activeMode = .toggle
                    toggleStopArmed = true
                    holdActivatedAt = nil
                    return .switchedToToggle
                }
                reset()
                return .stop
            case .holdActivated, .copyAgainTriggered:
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
                // Arms the press that follows, including when the session was
                // latched by `forceToggleMode()` while the key was still down.
                toggleStopArmed = true
                return nil
            case .copyAgainTriggered:
                return nil
            }
        }
    }

    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        toggleStopArmed = false
        holdActivatedAt = nil
    }

    func forceToggleMode() {
        activeMode = .toggle
        toggleStopArmed = false
        holdActivatedAt = nil
    }

    func reset() {
        activeMode = nil
        toggleStopArmed = false
        holdActivatedAt = nil
    }

    private func releaseIsTap(at timestamp: TimeInterval) -> Bool {
        guard let holdActivatedAt else { return false }
        return timestamp - holdActivatedAt < Self.tapThreshold
    }
}
