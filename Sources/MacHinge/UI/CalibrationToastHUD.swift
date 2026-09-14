import AppKit
import SwiftUI

@MainActor
public final class CalibrationToastHUD {
    public static let shared = CalibrationToastHUD()

    private var window: NSPanel?
    private var hideTimer: Timer?

    private init() {}

    public func show(angle: Double) {
        hideTimer?.invalidate()

        if let existing = window {
            existing.orderOut(nil)
            window = nil
        }

        let width: CGFloat = 390
        let height: CGFloat = 68

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.window = panel

        let contentView = ToastContentView(angle: angle)
        panel.contentView = NSHostingView(rootView: contentView)

        // Position at top center of main screen (just below menu bar / notch)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - (width / 2.0)
            let y = screenFrame.maxY - 80
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }

        panel.alphaValue = 0.0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let panel = self.window else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0.0
                }, completionHandler: {
                    Task { @MainActor in
                        panel.orderOut(nil)
                        self.window = nil
                    }
                })
            }
        }
    }
}

private struct ToastContentView: View {
    let angle: Double

    var body: some View {
        HStack(spacing: 12) {
            // App Icon / Status Badge
            toastIconView
                .layoutPriority(1)

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text("Preferred Angle Set")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("Normal screen anchor calibrated")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

            // Angle Readout Pill (Guaranteed Single Line, No Wrapping)
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text(String(format: "%.1f°", angle))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.green.opacity(0.3), lineWidth: 0.8)
            )
            .layoutPriority(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 390, height: 68)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.7))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var toastIconView: some View {
        if let icon = loadAppIcon() {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
    }

    private func loadAppIcon() -> NSImage? {
        if let bundleUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: bundleUrl) {
            return img
        }
        if let pngUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: pngUrl) {
            return img
        }
        if let bundlePath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: bundlePath) {
            return img
        }
        if let img = NSImage(contentsOfFile: "AppIcon.png") {
            return img
        }
        if let img = NSImage(contentsOfFile: "AppIcon.icns") {
            return img
        }
        if let appIcon = NSApplication.shared.applicationIconImage {
            return appIcon
        }
        return nil
    }
}
