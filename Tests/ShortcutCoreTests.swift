import Foundation

enum ShortcutCoreTests {
    static func run() {
        testBareFnHoldLifecycle()
        testDefaultShortcutSpecificityOrdering()
        testRightOptionPresetIsSideSpecific()
        testExactModifierMatching()
        testReducerHonorsExactModifierMatching()
        testRepeatedKeyDownDoesNotReactivate()
        testPasteAgainFiresOnLeadingEdgeOnly()
        testAddVocabularyFiresOnLeadingEdgeAndIsInertForDictation()
        testBackendResetClearsActiveBindings()
        testBindingMigrationAndIdentity()
        testConflictDetection()
        testHoldSessionControllerLifecycle()
        testManualSessionControls()
        testDoubleTapLatchesIntoToggle()
        testTapStopsLatchedSession()
        testLoneTapIsCancelled()
        testSecondTapAfterWindowDoesNotLatch()
        testLongHoldStopsOnRelease()
        testThresholdBoundaryCountsAsHold()
    }

    private static func testBareFnHoldLifecycle() {
        let configuration = ShortcutConfiguration(hold: .defaultHold)
        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: down.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(down.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(down.consumeDecision, .consume)
        TestSupport.expectEqual(up.emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(up.consumeDecision, .consume)
    }

    /// When two bindings go active at once the more specific one is emitted
    /// first.
    private static func testDefaultShortcutSpecificityOrdering() {
        let configuration = ShortcutConfiguration(
            hold: .defaultHold,
            copyAgain: ShortcutBinding.defaultHold.withAddedModifiers(.command)
        )
        let commandDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: commandDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let fnUp = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(fnDown.emittedEvents, [.copyAgainTriggered, .holdActivated])
        TestSupport.expectEqual(fnUp.emittedEvents, [.holdDeactivated])
    }

    private static func testRightOptionPresetIsSideSpecific() {
        let configuration = ShortcutConfiguration(hold: ShortcutPreset.rightOption.binding)
        let leftOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 58, isDown: true),
            configuration: configuration
        )
        let rightOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )

        TestSupport.expectEqual(leftOption.emittedEvents, [])
        TestSupport.expectEqual(rightOption.emittedEvents, [.holdActivated])
    }

    private static func testExactModifierMatching() {
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([54], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Right Command"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([55], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Left Command"
        )
        TestSupport.expect(
            !ShortcutBinding.exactModifierKeyCodesMatch([55, 56], exactModifierKeyCodes: [55]),
            "Unexpected Shift should invalidate an exact Command binding"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch(
                [55, 56],
                exactModifierKeyCodes: [55],
                permittedAdditionalExactMatchModifiers: [.shift]
            ),
            "Explicitly permitted Shift should not invalidate an exact Command binding"
        )
    }

    private static func testReducerHonorsExactModifierMatching() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55]
        )

        let rightCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 54, isDown: true),
            configuration: ShortcutConfiguration(hold: binding)
        ).state
        let rightCommandKey = ShortcutMatcher.reduce(
            state: rightCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding)
        )
        TestSupport.expectEqual(rightCommandKey.emittedEvents, [])

        let leftCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: ShortcutConfiguration(hold: binding)
        ).state
        let leftCommandKey = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding)
        )
        TestSupport.expectEqual(leftCommandKey.emittedEvents, [.holdActivated])

        let shiftedState = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .modifierChanged(keyCode: 56, isDown: true),
            configuration: ShortcutConfiguration(hold: binding)
        ).state
        let shiftedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding)
        )
        TestSupport.expectEqual(shiftedKey.emittedEvents, [])

        let permittedConfiguration = ShortcutConfiguration(
            hold: binding,
            permittedAdditionalExactMatchModifiers: [.shift]
        )
        let permittedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: permittedConfiguration
        )
        TestSupport.expectEqual(permittedKey.emittedEvents, [.holdActivated])
    }

    private static func testRepeatedKeyDownDoesNotReactivate() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: binding)
        let first = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: first.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )

        TestSupport.expectEqual(first.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(repeated.state, first.state)
        TestSupport.expectEqual(repeated.consumeDecision, .consume)
    }

    private static func testPasteAgainFiresOnLeadingEdgeOnly() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, copyAgain: binding)
        let firstDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: firstDown.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: repeated.state,
            event: .keyChanged(keyCode: 96, isDown: false, isRepeat: false),
            configuration: configuration
        )
        let secondDown = ShortcutMatcher.reduce(
            state: up.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )

        TestSupport.expectEqual(firstDown.emittedEvents, [.copyAgainTriggered])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(up.emittedEvents, [])
        TestSupport.expectEqual(secondDown.emittedEvents, [.copyAgainTriggered])
    }

    private static func testBackendResetClearsActiveBindings() {
        let configuration = ShortcutConfiguration(hold: .defaultHold)
        let fnDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let reset = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .backendReset,
            configuration: configuration
        )

        TestSupport.expectEqual(reset.emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(reset.consumeDecision, .passthrough)
        TestSupport.expect(reset.state.pressedKeyCodes.isEmpty, "Backend reset should clear pressed keys")
        TestSupport.expect(reset.state.pressedModifierKeyCodes.isEmpty, "Backend reset should clear modifiers")
        TestSupport.expect(!reset.state.holdIsActive, "Backend reset should clear active bindings")
    }

    private static func testBindingMigrationAndIdentity() {
        let stored = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [999, 61]
        )
        let normalized = stored.normalizedForStorageMigration()
        TestSupport.expectEqual(normalized.exactModifierKeyCodes, [61])
        TestSupport.expectEqual(normalized.modifiers, [.option])

        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command, .option],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55, 58]
        )
        let second = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.option, .command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [58, 55]
        )
        TestSupport.expectEqual(first.id, second.id)
    }

    private static func testConflictDetection() {
        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let same = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let different = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )

        TestSupport.expect(first.conflicts(with: same), "Equivalent bindings should conflict")
        TestSupport.expect(same.conflicts(with: first), "Conflict detection should be symmetric")
        TestSupport.expect(!first.conflicts(with: different), "Different primary keys should not conflict")
        TestSupport.expect(!first.conflicts(with: .disabled), "Disabled bindings should not conflict")
    }

    private static func testHoldSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: true, timestamp: 0),
            nil
        )
        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 1.0),
            .start(.hold)
        )
        // Held well past the tap threshold, so the release stops.
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 2.0),
            .stop
        )
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    /// `beginManual` and `forceToggleMode` back the menu bar's Start Dictating
    /// and the overlay's stop button, which bypass the shortcut entirely.
    private static func testManualSessionControls() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(
            controller.handle(event: .copyAgainTriggered, isTranscribing: false),
            nil
        )
        controller.beginManual(mode: .hold)
        TestSupport.expectEqual(controller.activeMode, .hold)
        controller.forceToggleMode()
        TestSupport.expectEqual(controller.activeMode, .toggle)
        controller.reset()
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.toggleStopArmed, false)
        TestSupport.expectEqual(controller.holdActivatedAt, nil)
    }

    /// A press released inside the tap threshold keeps recording and latches
    /// into toggle mode instead of stopping.
    /// Two quick taps latch into a hands-free session. The first release only
    /// opens the double-tap window; it must not latch on its own.
    private static func testDoubleTapLatchesIntoToggle() {
        let controller = DictationShortcutSessionController()

        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 10.0),
            .start(.hold)
        )
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 10.1),
            .awaitSecondTap
        )
        TestSupport.expectEqual(controller.activeMode, .hold)

        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 10.2),
            .switchedToToggle
        )
        TestSupport.expectEqual(controller.activeMode, .toggle)
        TestSupport.expect(
            !controller.toggleStopArmed,
            "The second tap's own press must not arm its own stop"
        )

        // Its release arms the stop.
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 10.25),
            nil
        )
        TestSupport.expect(controller.toggleStopArmed, "The second tap's release arms the stop")
    }

    /// Once latched, a single tap stops the session.
    private static func testTapStopsLatchedSession() {
        let controller = DictationShortcutSessionController()
        _ = controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 10.0)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 10.1)
        _ = controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 10.2)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 10.25)

        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 20.0),
            .stop
        )
        TestSupport.expectEqual(controller.activeMode, nil)

        // Releasing the stopping press must not start anything new.
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 20.05),
            nil
        )
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    /// A tap with no second tap is discarded rather than transcribed.
    private static func testLoneTapIsCancelled() {
        let controller = DictationShortcutSessionController()
        _ = controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 10.0)
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 10.1),
            .awaitSecondTap
        )

        // Still inside the window: nothing yet.
        TestSupport.expectEqual(
            controller.handleDoubleTapWindowExpiration(timestamp: 10.2),
            nil
        )
        TestSupport.expectEqual(controller.activeMode, .hold)

        TestSupport.expectEqual(
            controller.handleDoubleTapWindowExpiration(
                timestamp: 10.1 + DictationShortcutSessionController.doubleTapWindow
            ),
            .cancel
        )
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.awaitingSecondTapSince, nil)
    }

    /// Expiration is a no-op once the session has latched, so a late timer
    /// cannot cancel a running hands-free recording.
    private static func testSecondTapAfterWindowDoesNotLatch() {
        let controller = DictationShortcutSessionController()
        _ = controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 10.0)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 10.1)

        // A press arriving past the window is treated as a fresh first press
        // over the recording still in flight, not as a double tap.
        let late = 10.1 + DictationShortcutSessionController.doubleTapWindow + 0.05
        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: false, timestamp: late),
            nil
        )
        TestSupport.expectEqual(controller.activeMode, .hold)
        TestSupport.expectEqual(controller.awaitingSecondTapSince, nil)

        // A late expiration must not cancel it.
        TestSupport.expectEqual(controller.handleDoubleTapWindowExpiration(timestamp: late), nil)
        TestSupport.expectEqual(controller.activeMode, .hold)

        // Held past the threshold from that press, so it stops as a hold.
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: late + 1.0),
            .stop
        )
    }

    /// A press held past the threshold stops on release, as a hold.
    private static func testLongHoldStopsOnRelease() {
        let controller = DictationShortcutSessionController()

        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 10.0),
            .start(.hold)
        )
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 10.9),
            .stop
        )
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.toggleStopArmed, false)
    }

    /// A release exactly at the threshold is a hold, not a tap.
    private static func testThresholdBoundaryCountsAsHold() {
        let controller = DictationShortcutSessionController()
        _ = controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 0)

        TestSupport.expectEqual(
            controller.handle(
                event: .holdDeactivated,
                isTranscribing: false,
                timestamp: DictationShortcutSessionController.tapThreshold
            ),
            .stop
        )
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    /// Add to Vocabulary is a one-shot like Paste Again, and must never touch
    /// dictation state.
    private static func testAddVocabularyFiresOnLeadingEdgeAndIsInertForDictation() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, addVocabulary: binding)
        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: down.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: repeated.state,
            event: .keyChanged(keyCode: 96, isDown: false, isRepeat: false),
            configuration: configuration
        )

        TestSupport.expectEqual(down.emittedEvents, [.addVocabularyTriggered])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(up.emittedEvents, [])

        // It must not start, stop or disturb a dictation session.
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(
            controller.handle(event: .addVocabularyTriggered, isTranscribing: false, timestamp: 0),
            nil
        )
        TestSupport.expectEqual(controller.activeMode, nil)

        _ = controller.handle(event: .holdActivated, isTranscribing: false, timestamp: 1.0)
        TestSupport.expectEqual(
            controller.handle(event: .addVocabularyTriggered, isTranscribing: false, timestamp: 1.1),
            nil
        )
        TestSupport.expectEqual(controller.activeMode, .hold)
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, timestamp: 2.0),
            .stop
        )
    }
}
