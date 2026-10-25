import SwiftUI
import AppKit
import AVFoundation

@MainActor
final class PlaybackAppearance: ObservableObject {
    private var palettePixels: [UInt8]?
    @Published private(set) var accent: Color?
    @Published private(set) var scheme: ColorScheme = .dark
    private func adapt(_ brightness: Double) {
        // Hysteresis prevents controls flashing between appearances near the threshold.
        if brightness > 0.7 && scheme != .light { scheme = .light }
        else if brightness < 0.5 && scheme != .dark { scheme = .dark }
        if let palettePixels {
            let color = ArtworkPalette.color(pixels: palettePixels, darkSurface: scheme == .dark)
            if let color {
                let old = accent.flatMap { NSColor($0).usingColorSpace(.deviceRGB) }
                let next = NSColor(color).usingColorSpace(.deviceRGB)
                if let old, let next {
                    let delta = max(abs(old.redComponent - next.redComponent), abs(old.greenComponent - next.greenComponent), abs(old.blueComponent - next.blueComponent))
                    if delta > 0.10 { accent = color }
                } else { accent = color }
            }
        }
    }
    private func artworkPixels(_ data: Data) -> [UInt8]? {
        guard let image = ArtworkRendering.thumbnail(data, maximum: 32) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        guard rendered else { return nil }
        return bytes
    }
    func observe(song: Song?, video: AVPlayer?, active: Bool, darkLyrics: Bool, defaultScheme: ColorScheme? = nil, shouldSample: @escaping () -> Bool = { true }) async {
        guard active else { return }
        scheme = defaultScheme ?? .dark
        accent = nil
        palettePixels = nil
        if let data = song?.artworkData, let pixels = artworkPixels(data) {
            palettePixels = pixels
            if !darkLyrics && video == nil && defaultScheme == nil {
                var sum = 0.0
                for offset in stride(from: 0, to: pixels.count, by: 4) {
                    sum += 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])
                }
                adapt(sum / (256 * 255))
            }
            accent = ArtworkPalette.color(pixels: pixels, darkSurface: scheme == .dark)
        }
        if let item = video?.currentItem {
            // Attach once per item; app focus only gates sampling.
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
            item.add(output)
            defer { item.remove(output) }
            while !Task.isCancelled && video?.currentItem === item {
                // Skip CPU sampling when hidden, paused or in background. Keep
                // the lightweight native output attached until this item changes.
                if shouldSample(), NSApp.isActive, (video?.rate ?? 0) != 0 {
                    let time = video?.currentTime() ?? .zero
                    if output.hasNewPixelBuffer(forItemTime: time), let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                        if let sample = await Task.detached(priority: .utility, operation: { VideoFramePalette.sample(frame) }).value {
                            guard !Task.isCancelled else { break }
                            palettePixels = sample.pixels
                            adapt(sample.brightness)
                        }
                    }
                }
                do { try await Task.sleep(for: .milliseconds(2500)) } catch { break }
            }

        }
    }
}

/// Hide the native toolbar and its accessories together. Fullscreen presentation
/// also hides the separate native fullscreen host, preserving SwiftUI ownership.
struct PlaybackToolbarPresentation: NSViewRepresentable {
    let toolbarVisible: Bool
    var controlsVisible = true
    var reduceMotion = false
    var hideWindowChrome = false
    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }
    func updateNSView(_ view: AppearanceView, context: Context) {
        view.configure(playback: !toolbarVisible, hidden: hideWindowChrome || (!toolbarVisible && !controlsVisible))
    }
    static func dismantleNSView(_ view: AppearanceView, coordinator: ()) { view.restore() }

    final class AppearanceView: NSView {
        private struct Configuration: Equatable { var playback = false; var hidden = false }
        private var configuration = Configuration()
        private weak var trackedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var work: DispatchWorkItem?
        private var settleWork: DispatchWorkItem?
        private var savedTitle: NSWindow.TitleVisibility?
        private var savedTransparent: Bool?
        private var insertedFullSizeContent = false
        private var buttons: [(NSButton, Bool)] = []
        private var fullscreenHosts: [(NSWindow, CGFloat, Bool)] = []
        private var accessories: [(NSTitlebarAccessoryViewController, Bool, Bool, CGFloat)] = []
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard trackedWindow !== window else { return }
            restore()
            observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
            trackedWindow = window
            guard let window else { return }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.schedule() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // SwiftUI can install a replacement toolbar after a scene update.
                    // Reconcile only a real visibility mismatch; never poll per frame.
                    guard let self, self.configuration.hidden, let window = self.window,
                          window.toolbar?.isVisible != window.styleMask.contains(.fullScreen) || window.titlebarAccessoryViewControllers.contains(where: { !$0.isHidden }) else { return }
                    self.schedule()
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restoreFullscreenHosts() }
            })
            schedule()
        }
        func configure(playback: Bool, hidden: Bool) {
            let next = Configuration(playback: playback, hidden: playback && hidden)
            guard next != configuration else { return }
            configuration = next
            schedule()
        }
        private func schedule() {
            work?.cancel(); settleWork?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.apply()
                guard self.configuration.playback else { return }
                // Fullscreen can move native controls to a new host after layout.
                // One cancellable settling pass handles that transition without polling.
                let settled = DispatchWorkItem { [weak self] in self?.apply() }
                self.settleWork = settled
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: settled)
            }
            work = task
            DispatchQueue.main.async(execute: task)
        }
        /// Also called synchronously by native-window regression tests.
        func apply() {
            guard let window = trackedWindow ?? window else { return }
            guard configuration.playback else { restore(); return }
            let frame = window.frame
            defer {
                if !window.styleMask.contains(.fullScreen), window.frame != frame { window.setFrame(frame, display: false) }
            }
            if savedTitle == nil {
                savedTitle = window.titleVisibility
                savedTransparent = window.titlebarAppearsTransparent
                buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { kind in
                    window.standardWindowButton(kind).map { ($0, $0.isHidden) }
                }
            }
            window.titleVisibility = .hidden
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            if !window.styleMask.contains(.fullSizeContentView) {
                insertedFullSizeContent = true
                window.styleMask.insert(.fullSizeContentView)
            }
            for (button, originalHidden) in buttons {
                let hidden = configuration.hidden || originalHidden
                if button.isHidden != hidden { button.isHidden = hidden }
            }
            if configuration.hidden {
                for controller in window.titlebarAccessoryViewControllers {
                    if !accessories.contains(where: { $0.0 === controller }) {
                        accessories.append((controller, controller.isHidden, controller.view.isHidden, controller.fullScreenMinHeight))
                    }
                    if controller.fullScreenMinHeight != 0 { controller.fullScreenMinHeight = 0 }
                    // Hiding just the NSView leaves the accessory host and its background.
                    // The controller API collapses that host to zero height.
                    if !controller.isHidden { controller.isHidden = true }
                }
                if let toolbar = window.toolbar {
                    // Preserve the fullscreen host and hide it as a whole below.
                    // Collapsing its toolbar leaves a separately drawn titlebar strip.
                    let keepForFullscreenHost = window.styleMask.contains(.fullScreen)
                    if toolbar.isVisible != keepForFullscreenHost { toolbar.isVisible = keepForFullscreenHost }
                }
            } else {
                restoreToolbar(in: window)
            }
            if configuration.hidden && window.styleMask.contains(.fullScreen) {
                let candidates = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0)?.window } + window.titlebarAccessoryViewControllers.compactMap { $0.view.window }
                hideFullscreenHosts(candidates, excluding: window)
            } else { restoreFullscreenHosts() }
        }
        /// Hosts are resolved only through this window's native controls/accessories.
        /// Never hide the playback window itself or unrelated application windows.
        func hideFullscreenHosts(_ candidates: [NSWindow], excluding window: NSWindow) {
            for host in candidates where host !== window {
                if !fullscreenHosts.contains(where: { $0.0 === host }) { fullscreenHosts.append((host, host.alphaValue, host.ignoresMouseEvents)) }
                if host.alphaValue != 0 { host.alphaValue = 0 }
                if !host.ignoresMouseEvents { host.ignoresMouseEvents = true }
            }
        }
        private func restoreFullscreenHosts() {
            for (host, alpha, ignoresMouse) in fullscreenHosts {
                host.alphaValue = alpha; host.ignoresMouseEvents = ignoresMouse
            }
            fullscreenHosts.removeAll()
        }
        private func restoreToolbar(in window: NSWindow) {
            if window.toolbar?.isVisible == false { window.toolbar?.isVisible = true }
            for (controller, hidden, viewHidden, height) in accessories {
                controller.fullScreenMinHeight = height
                controller.isHidden = hidden
                controller.view.isHidden = viewHidden
            }
            accessories.removeAll()
        }
        func restore() {
            work?.cancel(); work = nil
            settleWork?.cancel(); settleWork = nil
            guard let window = trackedWindow ?? window else { return }
            restoreFullscreenHosts()
            let frame = window.frame
            defer {
                if !window.styleMask.contains(.fullScreen), window.frame != frame { window.setFrame(frame, display: false) }
            }
            restoreToolbar(in: window)
            if let savedTitle { window.titleVisibility = savedTitle }
            if let savedTransparent { window.titlebarAppearsTransparent = savedTransparent }
            for (button, hidden) in buttons { button.isHidden = hidden }
            if insertedFullSizeContent && !window.styleMask.contains(.fullScreen) {
                window.styleMask.remove(.fullSizeContentView)
                insertedFullSizeContent = false
            }
            buttons.removeAll(); savedTitle = nil; savedTransparent = nil
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// Resolve from the saved preference and the system preference, never from a
/// playback window or NSApp.effectiveAppearance (which can reflect that window).
@MainActor
final class ApplicationAppearance: ObservableObject {
    @Published private(set) var scheme: ColorScheme
    private var defaultsObserver: NSObjectProtocol?
    private var systemObserver: NSObjectProtocol?
    static func resolve(mode: String, systemIsDark: Bool) -> ColorScheme {
        switch mode {
        case "light": .light
        case "dark": .dark
        default: systemIsDark ? .dark : .light
        }
    }
    private static func current() -> ColorScheme {
        resolve(mode: UserDefaults.standard.string(forKey: "appearanceMode") ?? "system",
                systemIsDark: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
    }
    init() {
        scheme = Self.current()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        systemObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    private func refresh() {
        let resolved = Self.current()
        if scheme != resolved { scheme = resolved }
    }
    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let systemObserver { DistributedNotificationCenter.default().removeObserver(systemObserver) }
    }
}
