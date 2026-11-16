import AppKit
import NaviCore

public struct TriggerCapture: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case picked(DictationTrigger)
        case unsupportedKey
    }

    private enum Lone: Equatable, Sendable {
        case trigger(DictationTrigger)
        case unsupported
    }

    private var lone: Lone?
    private var wasHeld = false

    public private(set) var heldModifiers: UInt32 = 0
    public private(set) var holdsFn = false

    public init() {}

    public mutating func flagsChanged(flags: UInt) -> Outcome? {
        heldModifiers = KeyCombo.from(keyCode: 0, cocoaFlags: NSEvent.ModifierFlags(rawValue: flags)).modifiers
        holdsFn = NSEvent.ModifierFlags(rawValue: flags).contains(.function)
        let held = Self.heldKeys(flags: flags)
        defer { wasHeld = !held.isEmpty }
        if held.isEmpty {
            let finished = lone
            lone = nil
            switch finished {
            case let .trigger(trigger)?: return .picked(trigger)
            case .unsupported?: return .unsupportedKey
            case nil: return nil
            }
        }
        if !wasHeld, held.count == 1 {
            lone = held[0]
        } else if held.count > 1 {
            lone = nil
        }
        return nil
    }

    public mutating func keyDown(keyCode: UInt16, flags: UInt) -> KeyCombo {
        lone = nil
        return KeyCombo.from(keyCode: keyCode, cocoaFlags: NSEvent.ModifierFlags(rawValue: flags))
    }

    public mutating func reset() {
        lone = nil
        wasHeld = false
        heldModifiers = 0
        holdsFn = false
    }

    private static func heldKeys(flags: UInt) -> [Lone] {
        var held: [Lone] = []
        if NSEvent.ModifierFlags(rawValue: flags).contains(.function) { held.append(.trigger(.fn)) }
        for key in ModifierKey.allCases where flags & key.deviceMask != 0 {
            held.append(.trigger(.modifier(key)))
        }
        let unsupported = DeviceModifier.leftControl | DeviceModifier.leftShift | DeviceModifier.rightShift
            | DeviceModifier.leftCommand | DeviceModifier.leftOption
        let unsupportedCount = (0..<32).filter { flags & unsupported & (1 << $0) != 0 }.count
        held.append(contentsOf: Array(repeating: .unsupported, count: unsupportedCount))
        return held
    }
}
