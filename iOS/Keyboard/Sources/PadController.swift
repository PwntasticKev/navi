import Foundation
import NaviPad
import Observation
import os

@MainActor
@Observable
final class PadController {
    enum Mode: Equatable {
        case connecting
        case cold
        case needsFullAccess
        case live
    }

    private(set) var mode: Mode = .connecting
    private(set) var state: PadState = .off
    private(set) var notice: String?

    @ObservationIgnored var onInsert: (String) -> Void = { _ in }
    @ObservationIgnored var onNextKeyboard: () -> Void = {}
    @ObservationIgnored var onOpenApp: (URL) -> Void = { _ in }

    @ObservationIgnored private var channel: DarwinChannel?
    @ObservationIgnored private var store: PadStore?
    @ObservationIgnored private var lastPong: Date?
    @ObservationIgnored private var insertedID: UUID?
    @ObservationIgnored private var wantsStart = false
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var probe: Task<Void, Never>?
    @ObservationIgnored private var handoff: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.donovanhiland.navi.ios", category: "Pad")
    private static let pingWait: Duration = .milliseconds(450)
    private static let pingEvery: Duration = .milliseconds(1_200)
    private static let showResultFor: Duration = .milliseconds(900)

    func appear(fullAccess: Bool) {
        guard fullAccess, let store = PadStore(appGroup: PadConfig.appGroup) else {
            mode = .needsFullAccess
            return
        }
        self.store = store
        if channel == nil {
            let channel = DarwinChannel(prefix: PadConfig.signalPrefix)
            channel.observe([.pong, .changed]) { [weak self] signal in
                Task { @MainActor in self?.receive(signal) }
            }
            self.channel = channel
        }
        visible = false
        refresh()
        insertedID = state.resultID
        visible = true
        wantsStart = true
        mode = .connecting
        notice = nil
        startProbe()
    }

    func disappear() {
        visible = false
        probe?.cancel()
        handoff?.cancel()
        wantsStart = false
        if state.phase == .listening || state.phase == .cleaning { channel?.post(.cancel) }
    }

    func done() {
        channel?.post(state.phase == .failed ? .start : .stop)
    }

    func cancel() {
        handoff?.cancel()
        channel?.post(.cancel)
        onNextKeyboard()
    }

    func nextKeyboard() {
        if state.phase == .listening { channel?.post(.cancel) }
        onNextKeyboard()
    }

    func openApp() {
        wantsStart = true
        onOpenApp(PadConfig.startURL)
    }

    func couldNotOpenApp() {
        notice = "Open the Navi app to turn the mic on"
    }

    private func startProbe() {
        probe?.cancel()
        probe = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sent = Date.now
                channel?.post(.ping)
                try? await Task.sleep(for: Self.pingWait)
                guard !Task.isCancelled else { return }
                if let lastPong, lastPong >= sent {
                    becomeLive()
                } else if mode != .live || !state.isWarm(at: .now) {
                    mode = .cold
                }
                try? await Task.sleep(for: Self.pingEvery)
            }
        }
    }

    private func receive(_ signal: PadSignal) {
        switch signal {
        case .pong:
            lastPong = .now
            becomeLive()
        case .changed:
            refresh()
        case .start, .stop, .cancel, .ping:
            break
        }
    }

    private func becomeLive() {
        refresh()
        guard state.isWarm(at: .now) else { return }
        mode = .live
        if wantsStart, state.acceptsStart {
            wantsStart = false
            channel?.post(.start)
        }
    }

    private func refresh() {
        guard let store else { return }
        do {
            state = try store.read()
        } catch {
            Self.logger.error("State read failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if state.phase == .off, mode == .live { mode = .cold }
        if wantsStart, mode == .live, state.acceptsStart {
            wantsStart = false
            channel?.post(.start)
        }
        deliverResultIfNew()
    }

    private func deliverResultIfNew() {
        guard visible, state.phase == .done, let id = state.resultID, id != insertedID, let text = state.cleaned else { return }
        insertedID = id
        onInsert(text)
        handoff?.cancel()
        handoff = Task { [weak self] in
            try? await Task.sleep(for: Self.showResultFor)
            guard !Task.isCancelled else { return }
            self?.onNextKeyboard()
        }
    }
}
