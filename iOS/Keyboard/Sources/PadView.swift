import NaviPad
import SwiftUI

struct PadView: View {
    let pad: PadController

    var body: some View {
        ZStack {
            AuroraBackground(strength: 0.85, anchor: UnitPoint(x: 0.5, y: 0.95))
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.14), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
            content
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .foregroundStyle(.white)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch pad.mode {
        case .needsFullAccess:
            NoticePane(
                symbol: "lock.fill", title: "Turn on Allow Full Access",
                detail: "Settings › Navi › Keyboards. Navi needs it to reach the mic.",
                onNext: pad.nextKeyboard, onTap: nil
            )
        case .cold:
            NoticePane(
                symbol: "mic.fill", title: "Tap to start Navi",
                detail: pad.notice ?? "Opens Navi for a second to turn the mic on. Swipe back and talk.",
                onNext: pad.nextKeyboard, onTap: pad.openApp
            )
        case .connecting, .live:
            LivePane(pad: pad)
        }
    }
}

private struct LivePane: View {
    let pad: PadController

    private var phase: PadState.Phase { pad.mode == .connecting ? .ready : pad.state.phase }

    var body: some View {
        VStack(spacing: 0) {
            header
            words
                .frame(height: 72, alignment: .bottomLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.38)], startPoint: .top, endPoint: .bottom))
                .padding(.top, 10)
            WaveLines(level: pad.state.level, calm: phase != .listening)
                .frame(height: 54)
                .padding(.top, 6)
            Spacer(minLength: 0)
            controls
        }
    }

    private var header: some View {
        HStack {
            BrandWordmark()
            Spacer()
            status
        }
        .frame(height: 16)
    }

    @ViewBuilder
    private var status: some View {
        if phase == .listening, let start = pad.state.startedAt {
            HStack(spacing: 6) {
                RecordingDot()
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(Self.clock(context.date.timeIntervalSince(start)))
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
        } else if phase == .ready {
            Text("Starting").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var words: some View {
        switch phase {
        case .listening where pad.state.words.isEmpty, .ready, .off:
            Text("Listening…").foregroundStyle(.white.opacity(0.38)).font(Self.wordFont)
        case .listening:
            Text(Self.liveText(pad.state.words)).font(Self.wordFont).lineLimit(3).truncationMode(.head)
        case .cleaning:
            Text(pad.state.words.isEmpty ? "Cleaning up…" : pad.state.words).font(Self.wordFont).lineLimit(3).truncationMode(.head)
        case .done:
            Text(Self.diffText(raw: pad.state.words, cleaned: pad.state.cleaned ?? "")).font(Self.wordFont).lineLimit(3).truncationMode(.head)
        case .failed:
            Text(pad.state.message ?? "Something went wrong").foregroundStyle(.white.opacity(0.55)).font(Self.wordFont)
        }
    }

    private var controls: some View {
        HStack {
            GlassCircleButton(symbol: "xmark", label: "Cancel", action: pad.cancel)
            Spacer()
            DoneButton(
                busy: phase == .cleaning || phase == .done, retry: phase == .failed,
                enabled: phase == .listening || phase == .failed, action: pad.done
            )
            Spacer()
            GlassCircleButton(symbol: "keyboard", label: "Back to keyboard", dimmed: phase == .cleaning, action: pad.nextKeyboard)
        }
    }

    private static let wordFont = Font.system(size: 17, weight: .medium)

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func liveText(_ words: String) -> AttributedString {
        let parts = words.split(whereSeparator: \.isWhitespace)
        let tailCount = min(3, parts.count)
        let head = parts.dropLast(tailCount).joined(separator: " ")
        let tail = parts.suffix(tailCount).joined(separator: " ")
        var text = AttributedString(head.isEmpty ? "" : head + " ")
        text.foregroundColor = .white
        var newest = AttributedString(tail)
        newest.foregroundColor = NaviTheme.lavender
        return text + newest
    }

    static func diffText(raw: String, cleaned: String) -> AttributedString {
        CleanupDiff.pieces(raw: raw, cleaned: cleaned).enumerated().reduce(into: AttributedString()) { result, entry in
            var piece: AttributedString
            switch entry.element {
            case let .same(words):
                piece = AttributedString(words)
                piece.foregroundColor = .white
            case let .removed(words):
                piece = AttributedString(words)
                piece.foregroundColor = .white.opacity(0.3)
                piece.strikethroughStyle = .single
                piece.strikethroughColor = UIColor(NaviTheme.struck)
            case let .added(words):
                piece = AttributedString(words)
                piece.foregroundColor = NaviTheme.added
            }
            if entry.offset > 0 { result += AttributedString(" ") }
            result += piece
        }
    }
}

private struct DoneButton: View {
    let busy: Bool
    let retry: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small).tint(Color(hex: 0xC59BFF))
                    Text("Cleaning up")
                } else if retry {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .bold))
                    Text("Try again")
                } else {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                    Text("Done")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(busy ? .white.opacity(0.85) : Color(hex: 0x0B0D14))
            .frame(width: busy || retry ? 140 : 124, height: 50)
            .background(Capsule().fill(busy ? .white.opacity(0.1) : .white))
            .overlay(Capsule().stroke(.white.opacity(busy ? 0.14 : 0.3), lineWidth: 1))
            .shadow(color: busy ? .clear : Color(hex: 0x7882FF, opacity: 0.45), radius: 15, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.snappy(duration: 0.25), value: busy)
    }
}

private struct RecordingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(NaviTheme.recording)
            .frame(width: 6, height: 6)
            .background(Circle().fill(NaviTheme.recording.opacity(0.18)).frame(width: 12, height: 12))
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

private struct NoticePane: View {
    let symbol: String
    let title: String
    let detail: String
    let onNext: () -> Void
    let onTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BrandWordmark()
                Spacer()
                Text("Mic off").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
            }
            .frame(height: 16)
            Button { onTap?() } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(NaviTheme.orb).shadow(color: Color(hex: 0x6E78FF, opacity: 0.55), radius: 22)
                        Circle().stroke(Color(hex: 0x6E78FF, opacity: 0.12), lineWidth: 8).frame(width: 80, height: 80)
                        Image(systemName: symbol).font(.system(size: 23, weight: .medium))
                    }
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 10)
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 230)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            HStack {
                Spacer()
                GlassCircleButton(symbol: "keyboard", label: "Back to keyboard", action: onNext)
            }
        }
    }
}
