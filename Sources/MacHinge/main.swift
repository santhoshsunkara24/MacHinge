import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let controller = AnimationController()
    private var firstLaunchWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var debugWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup Menu Bar Item immediately
        MenuBarManager.shared.setup(with: controller)
        MenuBarManager.shared.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        MenuBarManager.shared.onOpenDebugStudio = { [weak self] in
            self?.openDebugWindow()
        }

        // 2. Setup Overlay
        OverlayWindowManager.shared.setupOverlay(with: controller)

        // 3. Start Animation & Sensor Engine
        controller.start()

        // 4. Setup Global System-Wide Hotkey
        GlobalHotkeyManager.shared.onCalibrateTriggered = { [weak self] in
            guard let controller = self?.controller else { return }
            controller.saveCurrentSensorAsPreferred()
            CalibrationToastHUD.shared.show(angle: controller.rawAngle)
        }
        GlobalHotkeyManager.shared.setup()

        // 5. Open Initial Window
        if !AppSettings.shared.hasCompletedOnboarding {
            openFirstLaunchWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    func openFirstLaunchWindow() {
        NSApp.setActivationPolicy(.regular)
        if firstLaunchWindow == nil {
            let view = FirstLaunchView(controller: controller) { [weak self] in
                self?.firstLaunchWindow?.close()
                self?.firstLaunchWindow = nil
                OverlayWindowManager.shared.showOverlay()
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Welcome to MacHinge"
            win.center()
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.delegate = self
            self.firstLaunchWindow = win
        }

        firstLaunchWindow?.makeKeyAndOrderFront(nil)
        firstLaunchWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let view = SettingsView(controller: controller)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 660),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "MacHinge Settings"
            win.center()
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.delegate = self
            self.settingsWindow = win
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDebugWindow() {
        NSApp.setActivationPolicy(.regular)
        if debugWindow == nil {
            let view = DebugStudioView(controller: controller)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "MacHinge Developer Dashboard"
            win.center()
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.delegate = self
            self.debugWindow = win
        }

        debugWindow?.makeKeyAndOrderFront(nil)
        debugWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep running in background when window is closed
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if settings window is closed
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        OverlayWindowManager.shared.hideOverlay()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
