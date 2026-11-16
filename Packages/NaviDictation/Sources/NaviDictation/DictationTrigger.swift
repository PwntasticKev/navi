import AppKit
import Carbon.HIToolbox
import NaviCore

public enum DictationTrigger: Codable, Equatable, Hashable, Sendable {
    case fn
    case modifier(ModifierKey)
    case shortcut(KeyCombo)

    public static let standard: DictationTrigger = .fn

    public static let choices: [DictationTrigger] = [.fn] + ModifierKey.allCases.map { .modifier($0) }

    public var name: String {
        switch self {
        case .fn: "fn"
        case let .modifier(key): key.name
        case let .shortcut(combo): combo.display
        }
    }

    public var keycaps: [String] {
        switch self {
        case .fn: ["fn"]
        case let .modifier(key): [key.name]
        case let .shortcut(combo): KeyCombo(keyCode: 0, modifiers: combo.modifiers).modifierSymbols + [combo.keyName]
        }
    }

    public var usesFnKey: Bool { self == .fn }

    public var shortcut: KeyCombo? {
        guard case let .shortcut(combo) = self else { return nil }
        return combo
    }

    func state(flags: UInt) -> (down: Bool, othersHeld: Bool)? {
        let cocoa = NSEvent.ModifierFlags(rawValue: flags)
        switch self {
        case .fn:
            let others = cocoa.intersection([.command, .option, .control, .shift])
            return (cocoa.contains(.function), !others.isEmpty)
        case let .modifier(key):
            let down = flags & key.deviceMask != 0
            let otherFamilies = cocoa.intersection([.command, .option, .control, .shift, .function])
                .subtracting(key.family)
            let twin = flags & key.twinDeviceMask != 0
            return (down, !otherFamilies.isEmpty || twin)
        case .shortcut:
            return nil
        }
    }
}

public enum ModifierKey: String, Codable, CaseIterable, Hashable, Sendable {
    case rightCommand
    case rightOption
    case rightControl

    public var name: String {
        switch self {
        case .rightCommand: "Right ⌘"
        case .rightOption: "Right ⌥"
        case .rightControl: "Right ⌃"
        }
    }

    var family: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand: .command
        case .rightOption: .option
        case .rightControl: .control
        }
    }

    var deviceMask: UInt {
        switch self {
        case .rightCommand: DeviceModifier.rightCommand
        case .rightOption: DeviceModifier.rightOption
        case .rightControl: DeviceModifier.rightControl
        }
    }

    var twinDeviceMask: UInt {
        switch self {
        case .rightCommand: DeviceModifier.leftCommand
        case .rightOption: DeviceModifier.leftOption
        case .rightControl: DeviceModifier.leftControl
        }
    }
}

enum DeviceModifier {
    static let leftControl: UInt = 0x0000_0001
    static let leftShift: UInt = 0x0000_0002
    static let rightShift: UInt = 0x0000_0004
    static let leftCommand: UInt = 0x0000_0008
    static let rightCommand: UInt = 0x0000_0010
    static let leftOption: UInt = 0x0000_0020
    static let rightOption: UInt = 0x0000_0040
    static let rightControl: UInt = 0x0000_2000
    static let all: UInt = leftControl | leftShift | rightShift | leftCommand | rightCommand
        | leftOption | rightOption | rightControl
}

extension KeyCombo {
    var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers & UInt32(controlKey) != 0 { symbols.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { symbols.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { symbols.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { symbols.append("⌘") }
        return symbols
    }
}

public struct DictationTriggerStore {
    static let key = "dictation.trigger"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> DictationTrigger {
        guard let data = defaults.data(forKey: Self.key),
              let trigger = try? JSONDecoder().decode(DictationTrigger.self, from: data) else {
            return .standard
        }
        return trigger
    }

    public func save(_ trigger: DictationTrigger) {
        guard trigger != .standard else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(trigger) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
