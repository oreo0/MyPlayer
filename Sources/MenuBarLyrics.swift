import Foundation
import AppKit
import Combine
import QuartzCore

@MainActor
final class MenuBarLyricsController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 180)
    private static var instance: MenuBarLyricsController?
    static func shared(for player: PlayerManager) -> MenuBarLyricsController {
        if let instance { return instance }
        let controller = MenuBarLyricsController(player: player)
        instance = controller
        return controller
    }
    private weak var player: PlayerManager?
    private let disc = BackgroundDiscView(frame: .zero)
    private var lyricsVisible = true
    private var background = false
    private var restore: (() -> Void)?
    private let marquee = StatusLyricMarquee(frame: .zero)
    private var cancellables = Set<AnyCancellable>()

    private init(player: PlayerManager) {
        super.init()
        self.player = player
        if let button = statusItem.button {
            button.title = ""
            marquee.frame = CGRect(x: 28, y: 0, width: 146, height: NSStatusBar.system.thickness)
            marquee.autoresizingMask = [.height]
            button.addSubview(marquee)
            disc.frame = CGRect(x: 3, y: 0, width: 22, height: button.bounds.height)
            disc.autoresizingMask = [.height]
            button.addSubview(disc)
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setVisible(UserDefaults.standard.object(forKey: "showMenuBarLyrics") as? Bool ?? true)

        player.clock.$time.combineLatest(player.$lyrics, player.$nowPlaying, player.$isPlaying)
            .map { time, lyrics, song, playing -> Presentation in
                let index = LRCParser.currentIndex(for: lyrics, at: time - (song?.lyricsOffset ?? 0))
                let line = index.flatMap { lyrics.indices.contains($0) ? lyrics[$0].text : nil } ?? song?.title ?? "MyPlayer"
                return Presentation(text: line, tooltip: line,
                                    song: song.map { "正在播放：\($0.title)" } ?? "未在播放", playing: playing)
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presentation in
                MainActor.assumeIsolated {
                    self?.marquee.setText(presentation.text)
                    self?.statusItem.button?.setAccessibilityLabel(presentation.tooltip)
                    self?.statusItem.button?.toolTip = presentation.tooltip
                    self?.refreshVisibility()
                }
            }.store(in: &cancellables)
    }
    private struct Presentation: Equatable {
        let text: String
        let tooltip: String
        let song: String
        let playing: Bool
    }
    func setVisible(_ visible: Bool) { lyricsVisible = visible; refreshVisibility() }
    func setBackground(_ value: Bool, restore: (() -> Void)? = nil) {
        background = value
        self.restore = value ? restore : nil
        refreshVisibility()
    }
    private func refreshVisibility() {
        statusItem.isVisible = background || lyricsVisible
        statusItem.length = lyricsVisible ? 180 : NSStatusItem.squareLength
        if let button = statusItem.button {
            let height = button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness
            marquee.frame = CGRect(x: 28, y: 0, width: 146, height: height)
            disc.frame = CGRect(x: 3, y: 0, width: 22, height: height)
        }
        marquee.isHidden = !lyricsVisible
        marquee.setActive(statusItem.isVisible && lyricsVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        disc.setPlaying(statusItem.isVisible && player?.isPlaying == true)
    }
    static func opensMenu(for event: NSEvent?) -> Bool {
        event?.type == .rightMouseUp || event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true
    }
    @objc private func clicked() {
        if Self.opensMenu(for: NSApp.currentEvent) {
            guard let button = statusItem.button else { return }
            let menu = PlaybackStatusMenu.make(song: player?.nowPlaying, target: self,
                                               hide: #selector(hideTapped), quit: #selector(quitTapped))
            // Track directly instead of re-entering the status button action.
            menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
            return
        }
        if let restore { restore(); return }
        _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
    }
    @objc private func hideTapped() {
        setVisible(false)
        UserDefaults.standard.set(false, forKey: "showMenuBarLyrics")
    }
    @objc private func quitTapped() { NSApp.terminate(nil) }
}

/// A fixed-width, non-interactive layer over the native menu button. Long lines
/// scroll on Core Animation; short lines stay still. No playback-frame timer.
final class StatusLyricMarquee: NSView {
    private let textLayer = CALayer()
    private let font = NSFont.menuBarFont(ofSize: 0)
    private(set) var displayedText = ""
    private var active = true
    private var dirty = true
    private var appliedSize: NSSize = .zero
    private(set) var animationRebuilds = 0
    var isScrolling: Bool { textLayer.animation(forKey: "statusScroll") != nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(textLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func setText(_ value: String) {
        let singleLine = value.components(separatedBy: .newlines).joined(separator: " ")
        guard displayedText != singleLine else { return }
        displayedText = singleLine; dirty = true; needsLayout = true
    }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value; dirty = true; needsLayout = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); dirty = true; needsLayout = true
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties(); dirty = true; needsLayout = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); dirty = true; needsLayout = true
        if window == nil { textLayer.removeAnimation(forKey: "statusScroll") }
    }
    override func layout() {
        super.layout()
        guard dirty || appliedSize != bounds.size else { return }
        dirty = false; appliedSize = bounds.size
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        effectiveAppearance.performAsCurrentDrawingAppearance {
            attributes[.foregroundColor] = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? NSColor.labelColor
        }
        let line = NSAttributedString(string: displayedText, attributes: attributes)
        let width = max(1, ceil(line.size().width) + 2)
        let height = ceil(font.ascender - font.descender + font.leading) + 2
        // One native-font line, redrawn only for content/appearance/size changes.
        // Own the animated layer so AppKit cannot reset a text-field transform.
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            line.draw(at: NSPoint(x: 1, y: 1))
            return true
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        textLayer.removeAnimation(forKey: "statusScroll")
        textLayer.transform = CATransform3DIdentity
        textLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        textLayer.frame = CGRect(x: 0, y: floor((bounds.height - height) / 2), width: width, height: height)
        let distance = max(0, width - bounds.width)
        if active && distance > 1 && bounds.width > 0 && window != nil {
            let travel = max(1.5, Double(distance) / 26)
            let total = travel * 2 + 2.8
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, 0, -distance, -distance, 0]
            animation.keyTimes = [0, NSNumber(value: 1.4 / total), NSNumber(value: (1.4 + travel) / total), NSNumber(value: (2.8 + travel) / total), 1]
            animation.duration = total; animation.repeatCount = .infinity
            textLayer.add(animation, forKey: "statusScroll"); animationRebuilds += 1
        }
        CATransaction.commit()
    }
}

/// Core Animation drives rotation without a per-frame main-thread timer.
final class BackgroundDiscView: NSView {
    private let disc = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(disc)
        disc.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 1, y: 1, width: 16, height: 16))
        path.addEllipse(in: CGRect(x: 7, y: 7, width: 4, height: 4))
        path.addArc(center: CGPoint(x: 9, y: 9), radius: 5.5, startAngle: 0.1, endAngle: 1.2, clockwise: false)
        path.move(to: CGPoint(x: 3.5, y: 9))
        path.addArc(center: CGPoint(x: 9, y: 9), radius: 5.5, startAngle: .pi, endAngle: .pi + 0.8, clockwise: false)
        disc.path = path
        disc.fillColor = nil
        disc.lineWidth = 1.4
        updateColor()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); disc.position = CGPoint(x: bounds.midX, y: bounds.midY) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColor() }
    private func updateColor() { effectiveAppearance.performAsCurrentDrawingAppearance { disc.strokeColor = NSColor.labelColor.cgColor } }
    func setPlaying(_ playing: Bool) {
        guard playing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { disc.removeAnimation(forKey: "spin"); return }
        guard disc.animation(forKey: "spin") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = 3
        rotation.repeatCount = .infinity
        disc.add(rotation, forKey: "spin")
    }
}

