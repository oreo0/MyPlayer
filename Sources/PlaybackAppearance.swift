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

struct PlaybackToolbarPresentation: NSViewRepresentable {
    let toolbarVisible: Bool
    var controlsVisible = true
    var reduceMotion = false
    var hideWindowChrome = false
    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }
    func updateNSView(_ view: AppearanceView, context: Context) { view.toolbarVisible = toolbarVisible; view.controlsVisible = controlsVisible; view.reduceMotion = reduceMotion; view.hideWindowChrome = hideWindowChrome; view.apply() }
    static func dismantleNSView(_ view: AppearanceView, coordinator: ()) {
        view.restore()
    }
    final class AppearanceView: NSView {
        var hideWindowChrome = false
        var controlsVisible = true
        var reduceMotion = false
        private var forcedChromeHidden = false
        private var appliedVisibility: Bool?
        private var visibilityTask: Task<Void, Never>?
        var toolbarVisible = true
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func restore() {
            visibilityTask?.cancel()
            for item in window?.toolbar?.items ?? [] { item.isHidden = false }
            window?.titleVisibility = .visible
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window?.standardWindowButton(kind)?.isHidden = false
            }
        }
        func apply() {
            let visibility: NSWindow.TitleVisibility = toolbarVisible ? .visible : .hidden
            if window?.titleVisibility != visibility { window?.titleVisibility = visibility }
            if let window, window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window?.standardWindowButton(kind), button.isHidden != hideWindowChrome { button.isHidden = hideWindowChrome }
            }
            if hideWindowChrome {
                forcedChromeHidden = true
                if let window, !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
                if window?.toolbar?.isVisible == true { window?.toolbar?.isVisible = false }
            } else if forcedChromeHidden {
                forcedChromeHidden = false
                window?.toolbar?.isVisible = true
            }
            let visible = controlsVisible
            if window?.toolbar != nil && appliedVisibility != visible {
                appliedVisibility = visible
                visibilityTask?.cancel()
                if visible {
                    for item in window?.toolbar?.items ?? [] { if item.isHidden { item.isHidden = false } }
                }
                visibilityTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !visible && !self.reduceMotion {
                        do { try await Task.sleep(for: .milliseconds(210)) } catch { return }
                    } else { await Task.yield() }
                    guard !Task.isCancelled, self.controlsVisible == visible else { return }
                    // Hide the NSToolbarItem itself: its native glass/bezel is outside
                    // the SwiftUI label's opacity. The toolbar remains installed.
                    for item in self.window?.toolbar?.items ?? [] {
                        if item.isHidden == visible { item.isHidden = !visible }
                    }
                    self.visibilityTask = nil
                }
            } else if !visible && visibilityTask == nil {
                for item in window?.toolbar?.items ?? [] where !item.isHidden { item.isHidden = true }
            }

        }
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
