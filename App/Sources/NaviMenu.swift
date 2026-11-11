import AppKit
import NaviCapture
import NaviCore

/// The Navi menu. It shows from the menu bar icon, and at the mouse with `⌥⇧⌘N`, which still works
/// when the icon is hidden behind the notch.
@MainActor
final class NaviMenu: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    /// The top-left corner of the menu the last time it opened, in screen points. Settings opens there.
    private var menuTopLeft: CGPoint = .zero
    /// True while the menu opens at the mouse (`⌥⇧⌘N`) rather than from the menu bar icon.
    private var opensAtMouse = false

    init(app: AppDelegate) {
        self.app = app
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Navi")
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Opens the menu at the mouse.
    func popUpAtMouse() {
        NSApp.activate()
        opensAtMouse = true
        defer { opensAtMouse = false }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Notes where the menu's top-left corner is: at the mouse, or under the menu bar icon.
    func menuWillOpen(_ menu: NSMenu) {
        if !opensAtMouse, let frame = statusItem.button?.window?.frame {
            menuTopLeft = CGPoint(x: frame.minX, y: frame.minY)
        } else {
            menuTopLeft = NSEvent.mouseLocation
        }
    }

    /// Rebuilds the items each time the menu opens, so the checkmarks are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let capture = app.capture

        menu.addItem(item("All-in-One", key: "5", [.command, .shift]) { capture.captureAllInOne() })
        menu.addItem(item("Capture Area", key: "4", [.command, .shift]) { capture.captureArea() })
        menu.addItem(item("Capture Window") { capture.captureWindow() })
        menu.addItem(item("Capture Fullscreen", key: "3", [.command, .shift]) { capture.captureFullscreen() })
        menu.addItem(item("Scrolling Capture", key: "4", [.command, .shift, .option]) { capture.captureScrolling() })
        menu.addItem(item("Capture Text", key: "t", [.command, .shift, .option]) { capture.captureText() })
        let timer = NSMenuItem(title: "Self-Timer", action: nil, keyEquivalent: "")
        timer.submenu = NSMenu()
        for seconds in [3, 5, 10] {
            timer.submenu?.addItem(item("\(seconds) Seconds") { capture.captureArea(timer: seconds) })
        }
        menu.addItem(timer)
        menu.addItem(.separator())
        if app.recording.isRecording {
            menu.addItem(item("Stop Recording", key: "5", [.command, .shift, .option]) { [app] in app.recording.stop() })
        } else {
            menu.addItem(item("Record Screen…", key: "5", [.command, .shift, .option]) { capture.pickRecordingRegion() })
        }
        menu.addItem(.separator())
        menu.addItem(item("Close All Cards") { capture.closeAllCards() })
        if capture.hasPins {
            menu.addItem(item("Unlock Pinned Shots") { capture.unlockPins() })
            menu.addItem(item("Close Pinned Shots") { capture.closeAllPins() })
        }
        menu.addItem(.separator())
        menu.addItem(shortcutItem("Open History", app.historyShortcut) { [app] in app.clipboard.togglePanel() })
        menu.addItem(.separator())
        menu.addItem(item("Settings…", key: ",", .command) { [app, weak self] in
            app.showSettings(at: self?.menuTopLeft ?? NSEvent.mouseLocation)
        })
        menu.addItem(item("Check for Updates…") { [app] in app.updater.checkForUpdates(nil) })
        menu.addItem(item("Quit Navi", key: "q", .command) { NSApp.terminate(nil) })
    }

    /// A menu item that shows `combo`. A one-character key uses the native key equivalent; other keys go in the title.
    private func shortcutItem(
        _ title: String, _ combo: KeyCombo, action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        guard combo.keyName.count == 1 else { return item("\(title) (\(combo.display))", action: action) }
        return item(title, key: combo.keyName.lowercased(), combo.cocoaModifiers, action: action)
    }

    /// A menu item that runs `action`. `key` only shows the shortcut; the global hot keys do the work.
    private func item(
        _ title: String, key: String = "", _ modifiers: NSEvent.ModifierFlags = [], on: Bool? = nil,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let item = ActionMenuItem(title: title, action: action)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifiers
        if let on { item.state = on ? .on : .off }
        return item
    }
}

/// A menu item with a closure.
@MainActor
private final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
