import SwiftUI
import AppKit
import QuartzCore

/// Native text and Core Animation: scrolling does not publish SwiftUI state or
/// rebuild library rows on every display frame.
struct ScrollingSongTitle: View {
    let text: String
    var height: CGFloat = 20
    var isActive = true
    var fontSize: CGFloat = NSFont.systemFontSize
    var textColor: NSColor = .labelColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TitleMarquee(text: text, active: isActive && !reduceMotion, fontSize: fontSize, textColor: textColor)
            .frame(height: height).clipped().help(text).accessibilityLabel(text)
    }
}
struct TitleMarquee: NSViewRepresentable {
    let text: String
    let active: Bool
    var fontSize: CGFloat = NSFont.systemFontSize
    var textColor: NSColor = .labelColor
    func makeNSView(context: Context) -> MarqueeView { MarqueeView() }
    func updateNSView(_ view: MarqueeView, context: Context) { view.configure(text: text, active: active, fontSize: fontSize, textColor: textColor) }
    final class MarqueeView: NSView {
        private let measure = NSTextField(labelWithString: "")
        private let viewport = CALayer()
        private let motion = CALayer()
        private let glyphs = CATextLayer()
        private var text = ""
        private var active = false
        private var color = NSColor.labelColor
        private var appliedViewport: CGRect = .null
        private var dirty = true
        private var measuredSize = NSSize.zero
        private(set) var animationRebuilds = 0
        var isScrolling: Bool { motion.animation(forKey: "titleScroll") != nil }
        private(set) var scrollDistance: CGFloat = 0
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true; layer?.masksToBounds = true
            viewport.masksToBounds = true
            layer?.addSublayer(viewport); viewport.addSublayer(motion); motion.addSublayer(glyphs)
            measure.font = .systemFont(ofSize: NSFont.systemFontSize)
            measure.maximumNumberOfLines = 1; measure.lineBreakMode = .byClipping
            glyphs.isWrapped = false; glyphs.truncationMode = .none; glyphs.alignmentMode = .left
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func configure(text: String, active: Bool, fontSize: CGFloat = NSFont.systemFontSize, textColor: NSColor = .labelColor, font: NSFont? = nil) {
            let font = font ?? NSFont.systemFont(ofSize: fontSize)
            let changed = self.text != text || self.active != active || measure.font != font
            if color != textColor { color = textColor; updateGlyphs() }
            guard changed else { return }
            self.text = text; self.active = active
            measure.font = font; measure.stringValue = text
            measuredSize = measure.fittingSize
            updateGlyphs(); dirty = true; needsLayout = true
        }
        private func updateGlyphs() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                glyphs.string = NSAttributedString(string: text, attributes: [.font: measure.font ?? .systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: color.usingColorSpace(.deviceRGB) ?? color])
            }
        }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateGlyphs() }
        override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); dirty = true; needsLayout = true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); dirty = true; needsLayout = true
            if window == nil { motion.removeAnimation(forKey: "titleScroll") }
        }
        private func textViewport() -> CGRect {
            var rect = bounds
            var ancestor = superview
            while let view = ancestor {
                if view is NSTableCellView || view is NSClipView {
                    let clip = convert(view.bounds, from: view)
                    let left = max(rect.minX, clip.minX), right = min(rect.maxX, clip.maxX)
                    rect = CGRect(x: left, y: bounds.minY, width: max(0, right - left), height: bounds.height)
                }
                ancestor = view.superview
            }
            return rect
        }
        override func viewWillStartLiveResize() {
            super.viewWillStartLiveResize()
            motion.removeAnimation(forKey: "titleScroll")
        }
        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            dirty = true; needsLayout = true
        }
        override func viewWillDraw() {
            if appliedViewport != textViewport() { dirty = true; layout() }
            super.viewWillDraw()
        }
        override func layout() {
            super.layout()
            let rect = textViewport()
            guard dirty || appliedViewport != rect else { return }
            dirty = false; appliedViewport = rect
            CATransaction.begin(); CATransaction.setDisableActions(true)
            motion.removeAnimation(forKey: "titleScroll"); motion.transform = CATransform3DIdentity
            viewport.frame = rect
            let fitting = measuredSize
            let textWidth = ceil(fitting.width) + 1
            let lineHeight = ceil(fitting.height)
            motion.frame = CGRect(x: 0, y: (rect.height - lineHeight) / 2, width: textWidth, height: lineHeight)
            glyphs.frame = motion.bounds
            glyphs.contentsScale = window?.backingScaleFactor ?? 2
            scrollDistance = max(0, textWidth - rect.width)
            if active && !inLiveResize && scrollDistance > 1 && rect.width > 0 && window != nil {
                let travel = max(1.5, Double(scrollDistance) / 26)
                let total = travel * 2 + 2.8
                let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
                animation.values = [0, 0, -scrollDistance, -scrollDistance, 0]
                animation.keyTimes = [0, NSNumber(value: 1.4 / total), NSNumber(value: (1.4 + travel) / total), NSNumber(value: (2.8 + travel) / total), 1]
                animation.duration = total; animation.repeatCount = .infinity; animation.calculationMode = .linear
                motion.add(animation, forKey: "titleScroll"); animationRebuilds += 1
            }
            CATransaction.commit()
        }
    }
}
