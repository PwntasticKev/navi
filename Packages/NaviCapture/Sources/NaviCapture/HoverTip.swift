import AppKit
import SwiftUI

@MainActor
enum HoverTip {
    private static let delay: Duration = .milliseconds(600)
    private static let gap: CGFloat = 14
    private static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)

    private static var panel: NSPanel?
    private static var pending: Task<Void, Never>?

    static func schedule(_ text: String) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            show(text, near: NSEvent.mouseLocation)
        }
    }

    static func hide() {
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
    }

    private static func show(_ text: String, near mouse: CGPoint) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: HoverTipLabel(text: text))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }?.frame ?? .zero
        let frame = CaptureGeometry.tipFrame(size: size, mouse: mouse, gap: gap, in: screen)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct HoverTipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .fixedSize()
    }
}

extension View {
    func hoverTip(_ text: String) -> some View {
        onHover { inside in inside ? HoverTip.schedule(text) : HoverTip.hide() }
            .onDisappear { HoverTip.hide() }
    }
}
