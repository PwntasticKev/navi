import AppKit
import Carbon.HIToolbox
import Foundation
import NaviCore
import Testing
@testable import NaviDictation

@Suite("DictationTrigger")
struct DictationTriggerTests {
    private let command = NSEvent.ModifierFlags.command.rawValue
    private let option = NSEvent.ModifierFlags.option.rawValue
    private let control = NSEvent.ModifierFlags.control.rawValue
    private let shift = NSEvent.ModifierFlags.shift.rawValue
    private let function = NSEvent.ModifierFlags.function.rawValue

    @Test("fn is down with the function flag, and other modifiers count as held")
    func fnState() {
        #expect(DictationTrigger.fn.state(flags: function)! == (true, false))
        #expect(DictationTrigger.fn.state(flags: function | command | DeviceModifier.leftCommand)! == (true, true))
        #expect(DictationTrigger.fn.state(flags: 0)! == (false, false))
    }

    @Test("right option is down only with its own device bit")
    func rightOptionState() {
        let trigger = DictationTrigger.modifier(.rightOption)
        #expect(trigger.state(flags: option | DeviceModifier.rightOption)! == (true, false))
        #expect(trigger.state(flags: option | DeviceModifier.leftOption)! == (false, true))
        #expect(trigger.state(flags: option | DeviceModifier.rightOption | DeviceModifier.leftOption)! == (true, true))
        #expect(trigger.state(flags: option | shift | DeviceModifier.rightOption | DeviceModifier.leftShift)! == (true, true))
        #expect(trigger.state(flags: option | function | DeviceModifier.rightOption)! == (true, true))
        #expect(trigger.state(flags: 0)! == (false, false))
    }

    @Test("right command and right control use their own bits")
    func otherRightKeys() {
        #expect(DictationTrigger.modifier(.rightCommand).state(flags: command | DeviceModifier.rightCommand)! == (true, false))
        #expect(DictationTrigger.modifier(.rightCommand).state(flags: command | DeviceModifier.leftCommand)! == (false, true))
        #expect(DictationTrigger.modifier(.rightControl).state(flags: control | DeviceModifier.rightControl)! == (true, false))
    }

    @Test("a shortcut trigger ignores modifier changes")
    func shortcutIgnoresFlags() {
        let trigger = DictationTrigger.shortcut(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)))
        #expect(trigger.state(flags: function) == nil)
        #expect(trigger.name == "⌃⌥Space")
        #expect(trigger.keycaps == ["⌃", "⌥", "Space"])
        #expect(!trigger.usesFnKey)
    }

    @Test("names and keycaps")
    func names() {
        #expect(DictationTrigger.fn.name == "fn")
        #expect(DictationTrigger.fn.usesFnKey)
        #expect(DictationTrigger.modifier(.rightCommand).name == "Right ⌘")
        #expect(DictationTrigger.modifier(.rightOption).keycaps == ["Right ⌥"])
        #expect(DictationTrigger.choices.first == .fn)
        #expect(DictationTrigger.choices.count == 1 + ModifierKey.allCases.count)
    }
}

@Suite("DictationTriggerStore")
struct DictationTriggerStoreTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "NaviDictationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test("a missing value loads fn")
    func missing() {
        withDefaults { #expect(DictationTriggerStore(defaults: $0).load() == .fn) }
    }

    @Test("every kind of trigger round trips")
    func roundTrip() {
        withDefaults { defaults in
            let store = DictationTriggerStore(defaults: defaults)
            let triggers: [DictationTrigger] = [
                .modifier(.rightOption),
                .modifier(.rightCommand),
                .shortcut(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))),
                .shortcut(KeyCombo(keyCode: UInt32(kVK_F13), modifiers: 0)),
            ]
            for trigger in triggers {
                store.save(trigger)
                #expect(store.load() == trigger)
            }
        }
    }

    @Test("saving fn removes the stored value")
    func savingDefaultClears() {
        withDefaults { defaults in
            let store = DictationTriggerStore(defaults: defaults)
            store.save(.modifier(.rightOption))
            store.save(.fn)
            #expect(defaults.object(forKey: DictationTriggerStore.key) == nil)
            #expect(store.load() == .fn)
        }
    }

    @Test("an unreadable value loads fn")
    func corrupt() {
        withDefaults { defaults in
            defaults.set(Data("nope".utf8), forKey: DictationTriggerStore.key)
            #expect(DictationTriggerStore(defaults: defaults).load() == .fn)
        }
    }
}

@Suite("TriggerCapture")
struct TriggerCaptureTests {
    private let option = NSEvent.ModifierFlags.option.rawValue
    private let command = NSEvent.ModifierFlags.command.rawValue
    private let shift = NSEvent.ModifierFlags.shift.rawValue
    private let function = NSEvent.ModifierFlags.function.rawValue

    @Test("a lone press and release of right option picks it")
    func loneRightOption() {
        var capture = TriggerCapture()
        #expect(capture.flagsChanged(flags: option | DeviceModifier.rightOption) == nil)
        #expect(capture.heldModifiers == UInt32(optionKey))
        #expect(capture.flagsChanged(flags: 0) == .picked(.modifier(.rightOption)))
        #expect(capture.heldModifiers == 0)
    }

    @Test("a lone press and release of fn picks fn")
    func loneFn() {
        var capture = TriggerCapture()
        _ = capture.flagsChanged(flags: function)
        #expect(capture.flagsChanged(flags: 0) == .picked(.fn))
    }

    @Test("a lone left modifier is not supported")
    func leftModifier() {
        var capture = TriggerCapture()
        _ = capture.flagsChanged(flags: command | DeviceModifier.leftCommand)
        #expect(capture.flagsChanged(flags: 0) == .unsupportedKey)
        _ = capture.flagsChanged(flags: shift | DeviceModifier.rightShift)
        #expect(capture.flagsChanged(flags: 0) == .unsupportedKey)
    }

    @Test("two modifiers together pick nothing")
    func twoModifiers() {
        var capture = TriggerCapture()
        _ = capture.flagsChanged(flags: option | DeviceModifier.rightOption)
        _ = capture.flagsChanged(flags: option | command | DeviceModifier.rightOption | DeviceModifier.leftCommand)
        _ = capture.flagsChanged(flags: option | DeviceModifier.rightOption)
        #expect(capture.flagsChanged(flags: 0) == nil)
    }

    @Test("a key pressed with the modifier makes a shortcut, and the release picks nothing")
    func keyMakesShortcut() {
        var capture = TriggerCapture()
        _ = capture.flagsChanged(flags: option | DeviceModifier.rightOption)
        let combo = capture.keyDown(keyCode: UInt16(kVK_Space), flags: option | DeviceModifier.rightOption)
        #expect(combo == KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)))
        #expect(capture.flagsChanged(flags: 0) == nil)
    }

    @Test("fn together with right option picks nothing")
    func fnWithRightOption() {
        var capture = TriggerCapture()
        _ = capture.flagsChanged(flags: function)
        #expect(capture.holdsFn)
        _ = capture.flagsChanged(flags: function | option | DeviceModifier.rightOption)
        _ = capture.flagsChanged(flags: function)
        #expect(capture.flagsChanged(flags: 0) == nil)
        #expect(!capture.holdsFn)
    }

    @Test("a lone right control picks it")
    func loneRightControl() {
        var capture = TriggerCapture()
        _ = capture.flagsChanged(flags: NSEvent.ModifierFlags.control.rawValue | DeviceModifier.rightControl)
        #expect(capture.flagsChanged(flags: 0) == .picked(.modifier(.rightControl)))
    }

    @Test("a key with no modifiers makes a bare shortcut")
    func bareKey() {
        var capture = TriggerCapture()
        #expect(capture.keyDown(keyCode: UInt16(kVK_F13), flags: 0) == KeyCombo(keyCode: UInt32(kVK_F13), modifiers: 0))
    }

    @Test("reset forgets a pressed modifier")
    func reset() {
        var capture = TriggerCapture()
        _ = capture.flagsChanged(flags: option | DeviceModifier.rightOption)
        capture.reset()
        #expect(capture.flagsChanged(flags: 0) == nil)
    }
}
