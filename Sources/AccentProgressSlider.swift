import SwiftUI
import AppKit
import QuartzCore

struct AccentProgressSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accent: Color
    let enabled: Bool
    let onEditingChanged: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Control {
        let slider = Control()
        slider.cell = Cell()
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel("播放进度")
        return slider
    }
    func updateNSView(_ view: Control, context: Context) {
        context.coordinator.owner = self
        view.minValue = range.lowerBound; view.maxValue = range.upperBound
        view.isEnabled = enabled
        if !view.editing { view.doubleValue = min(range.upperBound, max(range.lowerBound, value)) }
        (view.cell as? Cell)?.accent = NSColor(accent)
        view.beginEdit = { context.coordinator.owner.onEditingChanged(true) }
        view.endEdit = { context.coordinator.owner.onEditingChanged(false) }
        view.updateGlassKnob()
        view.needsDisplay = true
    }
    final class Coordinator: NSObject {
        var owner: AccentProgressSlider
        init(_ owner: AccentProgressSlider) { self.owner = owner }
        @objc func changed(_ slider: Control) {
            if !slider.editing { owner.onEditingChanged(true) }
            owner.value = slider.doubleValue
            if !slider.editing { owner.onEditingChanged(false) }
        }
    }
    final class Control: NSSlider {
        var editing = false
        var beginEdit: (() -> Void)?
        var endEdit: (() -> Void)?
        private let glassKnob = PassiveGlass()
        override init(frame: NSRect) {
            super.init(frame: frame)
            clipsToBounds = false
            glassKnob.style = .regular
            if #available(macOS 27.0, *) { glassKnob.effectIsInteractive = true }
            addSubview(glassKnob)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); updateGlassKnob() }
        override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
            updateGlassKnob()
            return super.sendAction(action, to: target)
        }
        func updateGlassKnob(animated: Bool = false) {
            guard let cell = cell as? Cell else { return }
            let knob = cell.knobRect(flipped: isFlipped).insetBy(dx: 1, dy: 1)
            guard knob.width > 0 && knob.height > 0 else { return }
            let scale: CGFloat = editing ? 1.35 : 1
            let frame = NSRect(x: knob.midX - knob.width * scale / 2,
                               y: knob.midY - knob.height * scale / 2,
                               width: knob.width * scale, height: knob.height * scale)
            glassKnob.cornerRadius = min(frame.width, frame.height) / 2
            glassKnob.tintColor = cell.accent.withAlphaComponent(0.35)
            glassKnob.alphaValue = isEnabled ? 1 : 0.4
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    glassKnob.animator().frame = frame
                }
            } else { glassKnob.frame = frame }
        }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            editing = true
            beginEdit?()
            updateGlassKnob(animated: true)
            super.mouseDown(with: event)
            endEdit?()
            editing = false
            updateGlassKnob(animated: true)
        }
    }
    final class PassiveGlass: NSGlassEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    final class Cell: NSSliderCell {
        var accent: NSColor = .controlAccentColor
        // A real NSGlassEffectView supplies the thumb. Native NSSlider still
        // owns mouse tracking, keyboard input and accessibility.
        override func drawKnob(_ knobRect: NSRect) { }
        override func drawBar(inside rect: NSRect, flipped: Bool) {
            let track = NSRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
            NSColor.secondaryLabelColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
            var filled = track
            filled.size.width *= CGFloat(min(1, max(0, (doubleValue - minValue) / max(0.001, maxValue - minValue))))
            accent.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
            NSBezierPath(roundedRect: filled, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
