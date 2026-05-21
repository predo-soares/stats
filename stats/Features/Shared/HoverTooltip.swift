import AppKit
import SwiftUI

final class HoverTooltipManager {
    private var tooltipPanel: NSPanel?

    func show(text: String) {
        hide()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let labelSize = CGSize(width: ceil(measured.width), height: ceil(measured.height))

        let hPad: CGFloat = 10
        let vPad: CGFloat = 6
        let contentSize = CGSize(width: labelSize.width + hPad * 2, height: labelSize.height + vPad * 2)

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .white
        label.frame = NSRect(x: hPad, y: vPad, width: labelSize.width, height: labelSize.height)

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        container.layer?.cornerRadius = 6
        container.layer?.cornerCurve = .continuous
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        container.layer?.borderWidth = 1
        container.addSubview(label)

        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x - contentSize.width / 2, y: mouse.y + 10)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.orderFront(nil)

        tooltipPanel = panel
    }

    func hide() {
        tooltipPanel?.orderOut(nil)
        tooltipPanel = nil
    }

    deinit {
        tooltipPanel?.orderOut(nil)
    }
}

private struct HoverTooltipModifier: ViewModifier {
    let text: String
    @State private var manager = HoverTooltipManager()

    func body(content: Content) -> some View {
        content
            .onHover { isHovered in
                if isHovered { manager.show(text: text) }
                else { manager.hide() }
            }
            .onDisappear { manager.hide() }
    }
}

extension View {
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltipModifier(text: text))
    }
}
