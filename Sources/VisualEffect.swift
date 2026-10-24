import SwiftUI
import AppKit
import Darwin

final class DesktopBackdropView: NSView {
    private let frosted = NSVisualEffectView()
    private weak var configuredWindow: NSWindow?
    private var appliedStyle: String?
    private var gaussian = false
    var style = "frosted" { didSet { if oldValue != style { update() } } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.material = .underWindowBackground
        frosted.autoresizingMask = [.width, .height]
        addSubview(frosted)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        if frosted.frame != bounds {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            frosted.frame = bounds
            CATransaction.commit()
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        update()
        DispatchQueue.main.async { [weak self] in self?.update() }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        update()
    }
    private func update() {
        guard let window else { return }
        if configuredWindow !== window {
            configuredWindow = window
            appliedStyle = nil
            window.titlebarAppearsTransparent = true
        }
        if appliedStyle != style {
            gaussian = false
            frosted.material = style == "gaussian" ? .hudWindow : .underWindowBackground
            let solid = style == "solid"
            frosted.isHidden = gaussian || solid
            window.isOpaque = solid
            window.backgroundColor = solid ? .windowBackgroundColor : .clear
            appliedStyle = style
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if style == "solid" {
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            } else {
                layer?.backgroundColor = gaussian ? NSColor.windowBackgroundColor.withAlphaComponent(0.20).cgColor : NSColor.clear.cgColor
            }
        }
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct NativeWindowBackground: NSViewRepresentable {
    var material = "frosted"
    func makeNSView(context: Context) -> DesktopBackdropView {
        let view = DesktopBackdropView()
        view.style = material
        return view
    }
    func updateNSView(_ view: DesktopBackdropView, context: Context) { view.style = material }
}
