import AppKit
import Carbon.HIToolbox
import NaviCapture
import NaviClipboard
import NaviDictation
import QuartzCore
import SwiftUI
import os

/// A borderless panel that takes key focus without making Navi the active app, like the History panel.
private final class SettingsWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The Settings panel, opened from the Navi menu (`⌘,`). It holds every on/off setting, the History
/// shortcut, and the permissions, so the menu keeps only actions. Esc, ⌘W, or clicking away closes it.
@MainActor
final class SettingsPanel: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private let model = SettingsModel()
    private lazy var panel: NSPanel = {
        let panel = Self.makePanel(model: model)
        panel.delegate = self
        return panel
    }()
    private var monitor: Any?
    private var isOpen = false
    private let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Settings")
    /// Goes up on every open and close, so a fade that finishes late does not hide a panel opened again.
    private var generation = 0

    private enum Motion {
        static let openDuration: TimeInterval = 0.16
        static let closeDuration: TimeInterval = 0.1
        /// How far the panel drops while it fades in, in points.
        static let drop: CGFloat = 4
    }

    init(app: AppDelegate) {
        self.app = app
        super.init()
        configure()
    }

    /// Builds the panel ahead of time, so the first open does not pay for the SwiftUI layout.
    func prepare() {
        _ = panel
    }

    /// Opens the panel with its top-left corner at `anchor` (where the Navi menu was), kept on screen,
    /// or brings it forward. It fades in and drops a few points; with Reduce Motion it only fades.
    func show(at anchor: CGPoint) {
        model.refresh()
        let panel = panel
        generation += 1
        guard !isOpen else {
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
            return
        }
        isOpen = true
        let target = Self.frame(size: panel.frame.size, topLeft: anchor)
        logger.info("Settings opened at \(String(describing: target), privacy: .public)")
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? target : target.offsetBy(dx: 0, dy: Motion.drop), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        installMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    /// Fades the panel out and hides it. The panel is kept for the next open. Safe to call more than once.
    func close() {
        guard isOpen else { return }
        isOpen = false
        logger.info("Settings closed")
        removeMonitor()
        generation += 1
        let closing = generation
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.closeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // A reopen during the fade wins.
                guard let self, self.generation == closing else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func makePanel(model: SettingsModel) -> NSPanel {
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        // A borderless panel has no title bar; without this the view leaves room for one at the top.
        hosting.safeAreaRegions = []
        let size = hosting.fittingSize
        let container = NaviPanelBackground.make(cornerRadius: SettingsMetrics.cornerRadius)
        container.frame = CGRect(origin: .zero, size: size)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let panel = SettingsWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    /// The frame of `size` with its top-left corner at `topLeft`, moved to stay inside that screen.
    private static func frame(size: CGSize, topLeft: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { NSMouseInRect(topLeft, $0.frame, false) } ?? NSScreen.main
        var origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    /// Esc and ⌘W close the panel. Returns true when the key was used.
    private func handle(_ event: NSEvent) -> Bool {
        let isCloseKey = event.keyCode == UInt16(kVK_Escape)
            || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w")
        guard isCloseKey else { return false }
        close()
        return true
    }

    /// Clicking away closes the panel, like the History panel and the shortcut recorder.
    func windowDidResignKey(_ notification: Notification) {
        logger.info("Settings lost key focus")
        close()
    }

    /// Coming back to the panel (for example from System Settings) reads the permissions again.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    // MARK: Model

    private func configure() {
        model.capture = captureToggles()
        model.talkToType = talkToTypeToggles()
        model.permissions = permissions()
        model.historyShortcut = { [app] in app.historyShortcut.display }
        model.changeHistoryShortcut = { [weak self, app] in
            self?.close()
            app.changeHistoryShortcut()
        }
        model.clearHistory = { [app] in app.inbox.clearUnpinned() }
        model.checkForUpdates = { [weak self, app] in
            self?.close()
            app.updater.checkForUpdates(nil)
        }
    }

    private func captureToggles() -> [SettingsModel.Toggle] {
        let settings = app.capture.settings
        return [
            .init(
                id: "screenshotKeys", title: "Navi Screenshot Keys",
                detail: "⇧⌘3, ⇧⌘4, ⇧⌘5 open Navi, not macOS",
                get: { settings.useNaviScreenshotKeys == true },
                set: { [app] in app.setUseNaviScreenshotKeys($0) }
            ),
            .init(
                id: "copyToClipboard", title: "Copy to Clipboard",
                get: { settings.copyToClipboard }, set: { settings.copyToClipboard = $0 }
            ),
            .init(
                id: "editAfterCapture", title: "Mark Up Before Copying",
                get: { settings.editAfterCapture }, set: { settings.editAfterCapture = $0 }
            ),
            .init(
                id: "hideDesktopIcons", title: "Hide Desktop Icons",
                get: { settings.hideDesktopIcons }, set: { settings.hideDesktopIcons = $0 }
            ),
        ]
    }

    private func talkToTypeToggles() -> [SettingsModel.Toggle] {
        let dictation = app.dictation
        let isOn: @MainActor () -> Bool = { dictation.isEnabled }
        return [
            .init(
                id: "talkToType", title: "Hold fn to Talk",
                get: isOn, set: { [app] in app.setTalkToType($0) }
            ),
            .init(
                id: "keepsMicrophoneReady", title: "Keep Microphone Ready",
                detail: "Faster start; mic dot always on",
                get: { dictation.keepsMicrophoneReady }, set: { dictation.keepsMicrophoneReady = $0 },
                isEnabled: isOn
            ),
        ]
    }

    private func permissions() -> [SettingsModel.Permission] {
        [
            .init(
                id: "accessibility", title: "Accessibility",
                isGranted: { ClipboardFeature.hasAccessibility },
                request: { ClipboardFeature.requestAccessibility() }
            ),
            .init(
                id: "screen", title: "Screen Recording",
                isGranted: { CaptureFeature.hasScreenAccess },
                request: { CaptureFeature.requestScreenAccess() }
            ),
            .init(
                id: "microphone", title: "Microphone and Speech",
                isGranted: { DictationPermissions.allGranted },
                request: { [weak self] in
                    Task { @MainActor in
                        _ = await DictationFeature.requestPermissions()
                        self?.model.refresh()
                    }
                }
            ),
        ]
    }
}
