import NaviPad
import SwiftUI
import UIKit

struct HomeView: View {
    let host: SessionHost
    @State private var practice = ""

    var body: some View {
        ZStack {
            AuroraBackground(strength: 0.8, anchor: UnitPoint(x: 0.5, y: 0.08)).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    SessionCard(host: host)
                    if let problem = host.problem { ProblemBanner(text: problem) }
                    SectionLabel(text: "Set up")
                    micStep
                    modelStep
                    keyboardStep
                    globeStep
                    SectionLabel(text: "Try it")
                    TextField("Tap here, then the globe", text: $practice, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 16))
                        .padding(14)
                        .glassCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Navi")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(NaviTheme.brand)
            Text("Talk to type, right from the keyboard")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var micStep: StepCard {
        StepCard(
            number: 1, title: "Microphone",
            detail: host.micAllowed ? "Allowed" : "Navi listens only while the mic is on.",
            done: host.micAllowed,
            action: host.micAllowed ? nil : StepAction(title: "Allow") { Task { await host.requestMic() } }
        )
    }

    private var modelStep: StepCard {
        StepCard(number: 2, title: "Speech model", detail: modelDetail, done: host.model == .ready, action: modelAction)
    }

    private var keyboardStep: StepCard {
        StepCard(
            number: 3, title: "Navi keyboard",
            detail: "In Settings, tap Keyboards, turn on Navi and Allow Full Access.",
            done: false, action: StepAction(title: "Open Settings") { openSettings() }
        )
    }

    private var globeStep: StepCard {
        StepCard(
            number: 4, title: "One tap from the globe",
            detail: "Remove the Emoji keyboard so the globe goes straight to Navi, or hold the globe and pick Navi.",
            done: false, action: nil
        )
    }

    private var modelDetail: String {
        switch host.model {
        case .missing: "Parakeet, about 500 MB. It stays on this iPhone. Apple speech works until it's ready."
        case .loading: "Getting Parakeet ready…"
        case .ready: "Parakeet is ready"
        case let .failed(reason): "Didn't load: \(reason)"
        }
    }

    private var modelAction: StepAction? {
        let host = host
        switch host.model {
        case .missing: return StepAction(title: "Download") { host.loadModel() }
        case .failed: return StepAction(title: "Try again") { host.loadModel() }
        case .loading, .ready: return nil
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct SessionCard: View {
    let host: SessionHost

    var body: some View {
        HStack(spacing: 14) {
            MicOrb(diameter: 46, ripples: host.isWarm)
                .saturation(host.isWarm ? 1 : 0)
                .opacity(host.isWarm ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(subtitle(at: context.date))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button(host.isWarm ? "Turn off" : "Turn on") {
                if host.isWarm { host.endSession() } else { Task { await host.startSession() } }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(host.isWarm ? .white : Color(hex: 0x0B0D14))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(host.isWarm ? .white.opacity(0.1) : .white))
        }
        .padding(16)
        .glassCard()
    }

    private var title: String {
        switch host.state.phase {
        case .off: "Mic is off"
        case .ready, .done, .failed: "Mic is on"
        case .listening: "Listening"
        case .cleaning: "Cleaning up"
        }
    }

    private func subtitle(at date: Date) -> String {
        if host.state.phase == .off { return host.state.message ?? "Turns on when you tap the Navi keyboard" }
        guard let until = host.state.readyUntil else { return "" }
        let minutes = max(1, Int((until.timeIntervalSince(date) / 60).rounded(.up)))
        return "Ready for \(minutes) min"
    }
}

private struct StepAction {
    let title: String
    let run: () -> Void
}

private struct StepCard: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let action: StepAction?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? NaviTheme.added.opacity(0.16) : .white.opacity(0.07))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(NaviTheme.added)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.title, action: action.run)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x9CC3FF))
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard()
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.top, 10)
            .padding(.leading, 4)
    }
}

private struct ProblemBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 13.5))
            .foregroundStyle(Color(hex: 0xFFB37A))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }
}

extension View {
    func glassCard() -> some View {
        background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}
