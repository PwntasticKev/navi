import AppKit
import Carbon.HIToolbox
import NaviCore
import NaviDictation
import SwiftUI

enum TalkKeyChange: Equatable {
    case applied
    case invalid(KeyComboError)
    case refused
    case unsupportedKey

    var message: String? {
        switch self {
        case .applied: nil
        case .invalid(.needsModifier), .invalid(.shiftOnly): "Use ⌘, ⌥ or ⌃ in the shortcut, or an F key on its own."
        case let .invalid(.inUse(name)): "Navi already uses this for \(name)."
        case .refused: "macOS or another app already uses this shortcut."
        case .unsupportedKey: "Use fn, or the right ⌘, ⌥ or ⌃ key on its own."
        }
    }
}

@Observable
@MainActor
final class TalkKeyState {
    var current: DictationTrigger = .standard
    var message: String?
    var held: UInt32 = 0
    var holdsFn = false
    var hint = ""
    var accepted: DictationTrigger?
    var shakes = 0
}

struct TalkKeyField: View {
    let state: TalkKeyState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 8) {
            HStack(spacing: 6) { caps }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(shape.fill(.primary.opacity(0.04)))
        .overlay(shape.strokeBorder(ringColor.opacity(state.accepted == nil && !reduceMotion && pulse ? 0.35 : 1), lineWidth: 2))
        .modifier(Shake(trigger: state.shakes, enabled: !reduceMotion))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var isHolding: Bool { state.held != 0 || state.holdsFn }

    private var ringColor: Color { state.message != nil ? .red : .accentColor }

    private var caption: String {
        if state.accepted != nil { return "Saved" }
        return isHolding ? "Let go, or press a key" : "Press the key or shortcut you want to hold"
    }

    @ViewBuilder private var caps: some View {
        if let accepted = state.accepted {
            ForEach(accepted.keycaps, id: \.self) { Keycap(text: $0, tint: .accentColor) }
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .padding(.leading, 4)
        } else if isHolding {
            let symbols = modifierSymbols.filter { state.held & $0.bit != 0 }.map(\.symbol)
            ForEach((state.holdsFn ? ["fn"] : []) + symbols, id: \.self) { Keycap(text: $0) }
            Keycap(text: nil)
        } else {
            ForEach(state.current.keycaps, id: \.self) { Keycap(text: $0) }.opacity(0.45)
        }
    }
}

struct TalkKeyChoices: View {
    let state: TalkKeyState
    let onPick: (DictationTrigger) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Or pick")
                .foregroundStyle(.secondary)
            ForEach(DictationTrigger.choices, id: \.self) { choice in
                let selected = (state.accepted ?? state.current) == choice
                Button { onPick(choice) } label: {
                    Text(choice.name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .disabled(state.accepted != nil)
    }
}

struct TalkKeyRecorderView: View {
    let state: TalkKeyState
    let onPick: (DictationTrigger) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Label("Talk to Type key", systemImage: "mic")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TalkKeyField(state: state)
            TalkKeyChoices(state: state, onPick: onPick)
            errorRow
            HStack {
                Text(state.hint)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Text("Cancel")
                        Text("esc")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.08)))
                    }
                }
                .buttonStyle(.plain)
                .disabled(state.accepted != nil)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 360)
    }

    private var errorRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let message = state.message {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).foregroundStyle(.red)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
    }
}

@MainActor
final class TalkKeyRecorder: NSObject, NSWindowDelegate {
    private static let savedPause: Duration = .milliseconds(500)
    private static let fadeDuration: TimeInterval = 0.2

    private let apply: (DictationTrigger) -> TalkKeyChange
    private let onClose: () -> Void
    private let state = TalkKeyState()
    private var capture = TriggerCapture()
    private var panel: NSPanel?
    private var monitor: Any?
    private var closing = false

    init(apply: @escaping (DictationTrigger) -> TalkKeyChange, onClose: @escaping () -> Void) {
        self.apply = apply
        self.onClose = onClose
    }

    func show(current: DictationTrigger, hint: String) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        state.current = current
        state.message = nil
        state.held = 0
        state.holdsFn = false
        state.hint = hint
        state.accepted = nil
        capture.reset()
        closing = false
        let hosting = NSHostingView(rootView: TalkKeyRecorderView(
            state: state,
            onPick: { [weak self] in self?.attempt($0) },
            onCancel: { [weak self] in self?.finish() }
        ))
        let panel = RecorderPanel.make(hosting: hosting)
        panel.delegate = self
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard !closing else { return true }
        let flags = event.modifierFlags.rawValue
        if event.type == .flagsChanged {
            let outcome = capture.flagsChanged(flags: flags)
            if capture.heldModifiers & ~state.held != 0 || (capture.holdsFn && !state.holdsFn) { state.message = nil }
            state.held = capture.heldModifiers
            state.holdsFn = capture.holdsFn
            switch outcome {
            case let .picked(trigger)?: attempt(trigger)
            case .unsupportedKey?: show(.unsupportedKey)
            case nil: break
            }
            return false
        }
        if event.keyCode == UInt16(kVK_Escape) {
            finish()
        } else if !event.isARepeat {
            attempt(.shortcut(capture.keyDown(keyCode: event.keyCode, flags: flags)))
        }
        return true
    }

    private func attempt(_ trigger: DictationTrigger) {
        let change = apply(trigger)
        guard change == .applied else {
            show(change)
            return
        }
        closing = true
        state.message = nil
        state.accepted = trigger
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.savedPause)
            self?.finish(fade: true)
        }
    }

    private func show(_ change: TalkKeyChange) {
        state.message = change.message
        state.shakes += 1
    }

    private func finish(fade: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        closing = true
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.delegate = nil
        onClose()
        if fade, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in panel.close() }
            }
        } else {
            panel.close()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        finish()
    }
}
