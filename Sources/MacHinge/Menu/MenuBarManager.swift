import AppKit
import SwiftUI
import Combine

@MainActor
public final class MenuBarManager: NSObject, NSMenuDelegate {
    public static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var cancellables = Set<AnyCancellable>()

    public var onOpenSettings: (@MainActor () -> Void)?
    public var onOpenDebugStudio: (@MainActor () -> Void)?

    private let settings = AppSettings.shared
    private weak var animationController: AnimationController?

    public func setup(with controller: AnimationController) {
        self.animationController = controller
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item
        item.isVisible = true

        if let button = item.button {
            button.image = createMenuBarIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "MacHinge"
        }

        let m = NSMenu()
        m.delegate = self
        self.menu = m
        item.menu = m

        rebuildMenu()

        // Subscribe to settings changes
        settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildMenu()
            }
        }.store(in: &cancellables)
    }

    public func createMenuBarIcon() -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: 36, height: 36, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return NSImage()
        }

        // Scale 2x for Retina display
        ctx.scaleBy(x: 2.0, y: 2.0)

        // Setup line style
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // 1. Draw geometric angle rays (vertex at (3.5, 3.5))
        // Top ray angled at comfortable viewing angle (~70°)
        // Bottom ray along horizontal baseline
        let anglePath = CGMutablePath()
        anglePath.move(to: CGPoint(x: 12.0, y: 14.5))
        anglePath.addLine(to: CGPoint(x: 3.5, y: 3.5))
        anglePath.addLine(to: CGPoint(x: 15.5, y: 3.5))

        ctx.addPath(anglePath)
        ctx.setLineWidth(1.8)
        ctx.strokePath()

        // 2. Draw angle measurement arc
        let arcPath = CGMutablePath()
        arcPath.addArc(center: CGPoint(x: 3.5, y: 3.5), radius: 6.2, startAngle: 0.0, endAngle: CGFloat.pi * 0.28, clockwise: false)
        ctx.addPath(arcPath)
        ctx.setLineWidth(1.2)
        ctx.strokePath()

        guard let cgImage = ctx.makeImage() else { return NSImage() }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 18, height: 18))
        nsImage.isTemplate = true
        return nsImage
    }

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    public func rebuildMenu() {
        guard let m = menu else { return }
        m.removeAllItems()

        // 1. App Title Header
        let titleItem = NSMenuItem(title: "MacHinge", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "MacHinge",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        titleItem.isEnabled = false
        m.addItem(titleItem)

        // 2. Enabled Toggle
        let enabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        m.addItem(enabledItem)

        m.addItem(NSMenuItem.separator())

        // 3. Preferred Angle Submenu
        let prefMenu = NSMenu()
        for preset in ViewingAnglePreset.allCases {
            let item = NSMenuItem(
                title: preset.rawValue,
                action: #selector(selectPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            item.state = (settings.preset == preset) ? .on : .off
            prefMenu.addItem(item)
        }

        let prefParentItem = NSMenuItem(title: "Preferred Angle", action: nil, keyEquivalent: "")
        prefParentItem.submenu = prefMenu
        m.addItem(prefParentItem)

        // 4. Effect Style Submenu
        let styleMenu = NSMenu()
        for style in VisualEffectStyle.allCases {
            let item = NSMenuItem(
                title: style.rawValue,
                action: #selector(selectStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style
            item.state = (settings.visualEffectStyle == style) ? .on : .off
            styleMenu.addItem(item)
        }
        let styleParentItem = NSMenuItem(title: "Effect Style", action: nil, keyEquivalent: "")
        styleParentItem.submenu = styleMenu
        m.addItem(styleParentItem)

        // 5. Quick "Set Current Angle" Action
        let curAngle = animationController?.rawAngle ?? settings.effectivePreferredAngle
        let setCurItem = NSMenuItem(
            title: String(format: "Set Current Angle (%.1f°)", curAngle),
            action: #selector(setCurrentAngleAction),
            keyEquivalent: settings.isHotkeyEnabled ? settings.hotkeyCombination.keyEquivalent : ""
        )
        if settings.isHotkeyEnabled {
            setCurItem.keyEquivalentModifierMask = settings.hotkeyCombination.modifierMask
        }
        setCurItem.target = self
        m.addItem(setCurItem)

        m.addItem(NSMenuItem.separator())

        // 5. Permission Notice (if permission is missing)
        if !ScreenCaptureEngine.hasScreenCaptureAccess() {
            let permItem = NSMenuItem(
                title: "Screen Recording Permission Required",
                action: #selector(openSettingsAction),
                keyEquivalent: ""
            )
            permItem.target = self
            permItem.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Permission Required")
            m.addItem(permItem)
            m.addItem(NSMenuItem.separator())
        }

        // 6. Settings Window
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        m.addItem(settingsItem)

        // 7. Show Diagnostic HUD Toggle
        let hudItem = NSMenuItem(
            title: "Show Diagnostic HUD",
            action: #selector(toggleDebugHUD),
            keyEquivalent: ""
        )
        hudItem.target = self
        hudItem.state = settings.showDebugControls ? .on : .off
        m.addItem(hudItem)

        // 8. Developer Dashboard (only shown if debug controls enabled)
        if settings.showDebugControls {
            let debugItem = NSMenuItem(
                title: "Developer Dashboard…",
                action: #selector(openDebugAction),
                keyEquivalent: "d"
            )
            debugItem.target = self
            m.addItem(debugItem)
        }

        m.addItem(NSMenuItem.separator())

        // 8. Quit
        let quitItem = NSMenuItem(
            title: "Quit MacHinge",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        m.addItem(quitItem)
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? ViewingAnglePreset {
            settings.preset = preset
        }
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? VisualEffectStyle {
            settings.visualEffectStyle = style
        }
    }

    @objc private func setCurrentAngleAction() {
        animationController?.saveCurrentSensorAsPreferred()
        if let angle = animationController?.rawAngle {
            CalibrationToastHUD.shared.show(angle: angle)
        }
    }

    @objc private func openSettingsAction() {
        onOpenSettings?()
    }

    @objc private func openDebugAction() {
        onOpenDebugStudio?()
    }

    @objc private func toggleDebugHUD() {
        settings.showDebugControls.toggle()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
