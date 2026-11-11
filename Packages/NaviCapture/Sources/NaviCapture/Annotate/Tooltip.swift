import SwiftUI

/// What a toolbar tooltip says: a short name and, when there is one, the key that does the same.
struct Tip: Equatable, Sendable {
    let title: String
    var shortcut: String?

    /// Names the button for `TooltipCenter`. Two buttons never share a tip.
    var id: String { "\(title)|\(shortcut ?? "")" }
}

/// The one tooltip the markup editor shows. Buttons tell it when the mouse enters or leaves;
/// it waits a moment before the first tip, then switches at once while the mouse moves along
/// the toolbar, like the macOS menu bar.
@MainActor
@Observable
final class TooltipCenter {
    /// The button whose tip shows now.
    private(set) var activeID: String?

    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var lastHidden = Date.distantPast

    static let showDelay: Duration = .milliseconds(450)
    static let hideDelay: Duration = .milliseconds(90)
    /// After a tip hides, the next one shows at once if the mouse gets there within this time.
    static let warmWindow: TimeInterval = 0.6

    init(activeID: String? = nil) {
        self.activeID = activeID
    }

    func hover(_ id: String, inside: Bool) {
        if inside { enter(id) } else { leave(id) }
    }

    /// Hides the tip at once, for a click.
    func dismiss() {
        pending?.cancel()
        if activeID != nil { lastHidden = .now }
        withAnimation(TooltipStyle.fade) { activeID = nil }
    }

    private func enter(_ id: String) {
        pending?.cancel()
        let isWarm = activeID != nil || Date.now.timeIntervalSince(lastHidden) < Self.warmWindow
        if isWarm {
            withAnimation(TooltipStyle.glide) { activeID = id }
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            guard !Task.isCancelled else { return }
            withAnimation(TooltipStyle.fade) { self?.activeID = id }
        }
    }

    private func leave(_ id: String) {
        guard activeID == id || activeID == nil else { return }
        pending?.cancel()
        guard activeID != nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self else { return }
            self.lastHidden = .now
            withAnimation(TooltipStyle.fade) { self.activeID = nil }
        }
    }
}

enum TooltipStyle {
    static let glide = Animation.spring(duration: 0.28, bounce: 0.12)
    static let fade = Animation.easeOut(duration: 0.16)
    /// While the pill glides, the old words leave fast and the new ones come in just after,
    /// so the two are never both readable.
    static let swapOut = Animation.easeOut(duration: 0.05)
    static let swapIn = Animation.easeOut(duration: 0.14).delay(0.04)
    /// Space between the button and the bubble.
    static let gap: CGFloat = 6
    /// The bubble never goes closer than this to the window edge.
    static let edgeMargin: CGFloat = 8
}

/// A hovered button's tip and where the button is.
struct TipAnchor {
    let tip: Tip
    let bounds: Anchor<CGRect>
}

struct TipAnchorKey: PreferenceKey {
    static let defaultValue: TipAnchor? = nil
    static func reduce(value: inout TipAnchor?, nextValue: () -> TipAnchor?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Shows `tip` under this view on hover. The view itself does not move or change size:
    /// the bubble is drawn by the nearest `tooltipLayer` above everything else. With no
    /// layer, it falls back to the system tooltip.
    func tooltip(_ tip: Tip) -> some View {
        modifier(TooltipSource(tip: tip))
    }

    /// Draws the active tooltip above this view. Put it on the root view of the window.
    func tooltipLayer(_ center: TooltipCenter) -> some View {
        environment(center).overlayPreferenceValue(TipAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if center.activeID != nil, let anchor {
                    TooltipBubble(tip: anchor.tip)
                        .modifier(TooltipPlacement(button: proxy[anchor.bounds], container: proxy.size))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                                .combined(with: .offset(y: -3)),
                            removal: .opacity
                        ))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct TooltipSource: ViewModifier {
    let tip: Tip
    @Environment(TooltipCenter.self) private var center: TooltipCenter?

    func body(content: Content) -> some View {
        if let center {
            custom(content, center: center)
        } else {
            content.help(tip.shortcut.map { "\(tip.title) (\($0))" } ?? tip.title)
        }
    }

    private func custom(_ content: Content, center: TooltipCenter) -> some View {
        let id = tip.id
        // Read here, in `body`, so SwiftUI redraws this view when the active tip changes.
        let isActive = center.activeID == id
        return content
            .onHover { center.hover(id, inside: $0) }
            .simultaneousGesture(TapGesture().onEnded { center.dismiss() })
            .anchorPreference(key: TipAnchorKey.self, value: .bounds) { bounds in
                isActive ? TipAnchor(tip: tip, bounds: bounds) : nil
            }
            .accessibilityHint(tip.title)
    }
}

/// Centers the bubble under the button, kept inside the window. When there is no room
/// below, the bubble goes above.
private struct TooltipPlacement: ViewModifier {
    let button: CGRect
    let container: CGSize
    @State private var size = CGSize.zero

    func body(content: Content) -> some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .position(x: x, y: y)
            .animation(TooltipStyle.glide, value: button)
    }

    private var y: CGFloat {
        let below = button.maxY + TooltipStyle.gap + size.height / 2
        let fitsBelow = below + size.height / 2 + TooltipStyle.edgeMargin <= container.height
        return fitsBelow ? below : button.minY - TooltipStyle.gap - size.height / 2
    }

    private var x: CGFloat {
        let half = size.width / 2
        let low = TooltipStyle.edgeMargin + half
        let high = container.width - TooltipStyle.edgeMargin - half
        return low <= high ? min(max(button.midX, low), high) : container.width / 2
    }
}

/// A small dark pill: the name, then the key in a keycap. When the tip changes, the pill
/// glides to its new width and the old words fade out inside it, clipped, so the two
/// labels never spill past the edge.
struct TooltipBubble: View {
    let tip: Tip
    @State private var labelWidth: CGFloat?

    var body: some View {
        ZStack {
            TooltipLabel(tip: tip)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    if labelWidth == nil {
                        labelWidth = width
                    } else {
                        withAnimation(TooltipStyle.glide) { labelWidth = width }
                    }
                }
                .id(tip.id)
                .transition(.asymmetric(
                    insertion: .opacity.animation(TooltipStyle.swapIn),
                    removal: .opacity.animation(TooltipStyle.swapOut)
                ))
        }
        .frame(width: labelWidth)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(white: 0.11).opacity(0.96))
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
    }
}

private struct TooltipLabel: View {
    let tip: Tip

    var body: some View {
        HStack(spacing: 6) {
            Text(tip.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
            if let shortcut = tip.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 15)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            }
        }
        .lineLimit(1)
        .padding(.leading, 8)
        .padding(.trailing, tip.shortcut == nil ? 8 : 4)
        .padding(.vertical, 4)
    }
}
