import Foundation

@MainActor
final class SetupTestHotkeyHarness: ObservableObject {
    private let hotkeyManager = HotkeyManager()
    private let sessionController = DictationShortcutSessionController()
    private var pendingStartTask: Task<Void, Never>?
    private var doubleTapWindowTask: Task<Void, Never>?
    private var pendingStartMode: RecordingTriggerMode?

    var isTranscribing = false
    var onAction: ((DictationShortcutAction) -> Void)?

    func start(configuration: ShortcutConfiguration, startDelay: TimeInterval) throws {
        hotkeyManager.onShortcutEvent = { [weak self] event in
            guard let self else { return }
            let action = self.sessionController.handle(event: event, isTranscribing: self.isTranscribing)
            guard let action else { return }
            self.handle(action: action, startDelay: startDelay)
        }
        cancelPendingStart()
        sessionController.reset()
        isTranscribing = false
        try hotkeyManager.start(configuration: configuration)
    }

    func stop() {
        hotkeyManager.stop()
        cancelDoubleTapWindow()
        cancelPendingStart()
        onAction = nil
        sessionController.reset()
        isTranscribing = false
    }

    func resetSession() {
        cancelDoubleTapWindow()
        cancelPendingStart()
        sessionController.reset()
    }

    private func handle(action: DictationShortcutAction, startDelay: TimeInterval) {
        switch action {
        case .start(let mode):
            scheduleStart(mode: mode, delay: startDelay)
        case .stop:
            cancelDoubleTapWindow()
            cancelPendingStart()
            DispatchQueue.main.async {
                self.onAction?(action)
            }
        case .switchedToToggle:
            cancelDoubleTapWindow()
            if pendingStartMode != nil {
                pendingStartMode = .toggle
            }
            DispatchQueue.main.async {
                self.onAction?(action)
            }
        case .awaitSecondTap:
            armDoubleTapWindow()
        case .cancel:
            cancelPendingStart()
            DispatchQueue.main.async {
                self.onAction?(action)
            }
        }
    }

    private func armDoubleTapWindow() {
        cancelDoubleTapWindow()
        doubleTapWindowTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(DictationShortcutSessionController.doubleTapWindow * 1_000_000_000)
                )
            } catch {
                return
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.doubleTapWindowTask = nil
                guard let action = self.sessionController.handleDoubleTapWindowExpiration(),
                      action == .cancel else { return }
                self.handle(action: action, startDelay: 0)
            }
        }
    }

    private func cancelDoubleTapWindow() {
        doubleTapWindowTask?.cancel()
        doubleTapWindowTask = nil
    }

    private func scheduleStart(mode: RecordingTriggerMode, delay: TimeInterval) {
        cancelPendingStart(resetMode: false)
        pendingStartMode = mode

        guard delay > 0 else {
            pendingStartMode = nil
            DispatchQueue.main.async {
                self.onAction?(.start(mode))
            }
            return
        }

        pendingStartTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            await MainActor.run { [weak self] in
                guard let self, let pendingMode = self.pendingStartMode else { return }
                self.pendingStartTask = nil
                self.pendingStartMode = nil
                self.onAction?(.start(pendingMode))
            }
        }
    }

    private func cancelPendingStart(resetMode: Bool = true) {
        pendingStartTask?.cancel()
        pendingStartTask = nil
        if resetMode {
            pendingStartMode = nil
        }
    }
}
