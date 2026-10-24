import Foundation
import SwiftUI
import AppKit
import CoreVideo
import Darwin

/// Reproduce retained SwiftUI Table/List row initialization, not only AppKit rows.
private struct StartupRows57: View {
    let songs = (0..<40).map { Song(path: "/test/\($0).mp3", title: "Song \($0)", artist: "Artist", album: "Album", duration: 20) }
    @State private var selected = Set<UUID>()
    var applySurface = true
    var body: some View {
        HStack {
            Table(songs, selection: $selected) {
                TableColumn("歌曲", value: \.title)
                TableColumn("歌手", value: \.artist)
            }.background { if applySurface { TableTransparency() } }
            List(songs) { Text($0.title) }
                .background(TableTransparency(selectionOnly: true))
        }.frame(minWidth: 600, minHeight: 300)
    }
}

@MainActor final class ChromeProbe65: ObservableObject { @Published var visible = true }
private struct PlaybackCanvas65: View {
    let player: PlayerManager
    @ObservedObject var chrome: ChromeProbe65
    var body: some View {
        Color.black.overlay {
            GeometryReader { geometry in
                NativePlayerBar(player: player, isActive: chrome.visible, showPlaying: {}, showThumbnail: false)
                    .frame(width: geometry.size.width * 2 / 3)
                    .background(CanvasClickPassthrough(enabled: chrome.visible))
                    .opacity(chrome.visible ? 1 : 0)
                    .allowsHitTesting(chrome.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@MainActor final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { 100 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { NSTextField(labelWithString: "Track \(row)") }
}
@main struct PerformanceTests {
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }
    static func childFootprint(_ file: URL) throws -> UInt64 {
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        task.arguments = ["--memory", file.path]; task.standardOutput = output
        try task.run(); task.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        precondition(task.terminationStatus == 0)
        return UInt64(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--memory" {
            let songs = try autoreleasepool { try JSONDecoder().decode([Song].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) }
            let bytes = footprint()
            withExtendedLifetime(songs) { print(bytes) }
            return
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let startupWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        startupWindow.styleMask.insert(.fullSizeContentView)
        startupWindow.toolbar = NSToolbar(identifier: "Startup70")
        startupWindow.titlebarAppearsTransparent = true
        startupWindow.contentView = NSHostingView(rootView: StartupRows57())
        startupWindow.contentView?.layoutSubtreeIfNeeded()
        startupWindow.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let initialTable = twoColumnTable(startupWindow.contentView!)!
        precondition(initialTable.enclosingScrollView?.automaticallyAdjustsContentInsets == true, "first launch must preserve native toolbar insets before any resize or click")
        if let header = initialTable.headerView {
            precondition(header.convert(header.bounds, to: nil).maxY <= startupWindow.contentLayoutRect.maxY + 1, "first-launch header must be clickable below toolbar before any resize")
        }
        for index in 0..<12 {
            startupWindow.setContentSize(NSSize(width: 900 + index * 5, height: 600 + index * 3))
            startupWindow.contentView?.layoutSubtreeIfNeeded()
            startupWindow.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        func verifyTables(_ view: NSView) {
            if let table = view as? NSTableView {
                precondition(table.gridStyleMask.isEmpty, "item separators must be disabled")

            }
            view.subviews.forEach(verifyTables)
        }
        if let root = startupWindow.contentView { verifyTables(root) }
        for height: CGFloat in [20, 32, 40, 72] {
            let radius = SurfaceCorners.selectionRadius(height: height)
            precondition(radius > 0 && radius < height / 2)
        }
        func twoColumnTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.numberOfColumns == 2 { return table }
            for child in view.subviews { if let table = twoColumnTable(child) { return table } }
            return nil
        }
        let defaultWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        defaultWindow.contentView = NSHostingView(rootView: StartupRows57(applySurface: false))
        defaultWindow.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let actualTable = twoColumnTable(startupWindow.contentView!)!, defaultTable = twoColumnTable(defaultWindow.contentView!)!
        precondition(actualTable.rowHeight == defaultTable.rowHeight && actualTable.usesAutomaticRowHeights == defaultTable.usesAutomaticRowHeights, "library surface must preserve native default row sizing")
        precondition(actualTable.enclosingScrollView?.automaticallyAdjustsContentInsets == true, "native toolbar inset adjustment must remain enabled")
        if let header = actualTable.headerView {
            let top = header.convert(header.bounds, to: nil).maxY
            precondition(top <= startupWindow.contentLayoutRect.maxY + 1, "table header must remain below the native toolbar")
        }
        print("PASS: toolbar startup preserves automatic top content inset and unobscured table header")
        defaultWindow.contentView = nil
        startupWindow.contentView = nil
        print("PASS: SwiftUI Table/List startup and resize without separator initialization exceptions")
        let canvasWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        let surface = CanvasClickSurface.Surface(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        canvasWindow.contentView!.addSubview(surface)
        var visible = true
        surface.onClick = { _ in visible.toggle() }
        let empty = NSPoint(x: 300, y: 250)
        precondition(surface.hitTest(empty) === surface, "empty playback canvas must receive clicks")
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: empty, modifierFlags: [], timestamp: 0, windowNumber: canvasWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        surface.mouseDown(with: click)
        precondition(!visible, "first empty click hides controls")
        surface.mouseDown(with: click)
        precondition(visible, "second empty click restores controls")
        surface.shouldCapture = { $0.x < 650 }
        precondition(surface.hitTest(NSPoint(x: 700, y: 250)) == nil, "queue panel must keep its mouse events")
        let host = NSHostingView(rootView: Color.black.overlay {
            CanvasClickSurface(shouldCapture: { _ in true }, onClick: { _ in visible.toggle() })
        })
        canvasWindow.contentView = host
        host.layoutSubtreeIfNeeded(); canvasWindow.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        precondition(host.hitTest(empty) is CanvasClickSurface.Surface, "real SwiftUI overlay must route empty clicks to canvas receiver")
        canvasWindow.contentView = nil
        print("PASS: empty-canvas native hit testing, consecutive hide/show clicks, queue exclusion")
        // Render the real adaptive title at generous and constrained widths.
        func marquee(in view: NSView) -> TitleMarquee.MarqueeView? {
            if let found = view as? TitleMarquee.MarqueeView { return found }
            for child in view.subviews { if let found = marquee(in: child) { return found } }
            return nil
        }
        let titleWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        for (text, available) in [("短歌名", CGFloat(400)), ("A very long song or video title that cannot fit in the available toolbar space", CGFloat(80))] {
            let host = NSHostingView(rootView: AdaptiveToolbarSongTitle(text: text, active: true, color: .labelColor).frame(width: available, height: 30))
            host.frame = NSRect(x: 0, y: 0, width: available, height: 30)
            titleWindow.contentView!.addSubview(host)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            guard let label = marquee(in: host) else { preconditionFailure("adaptive title must use the native marquee") }
            label.layout()
            let natural = AdaptiveToolbarSongTitle.naturalWidth(text)
            precondition(abs(label.bounds.width - min(natural, available)) < 2, "title should grow naturally and compress to available width")
            // Offscreen AppKit removes presentation animations at transaction
            // commit. Check a fresh activation after final geometry is settled.
            label.configure(text: text, active: false); label.layout()
            let before = label.animationRebuilds
            label.configure(text: text, active: true); label.layout()
            precondition((label.animationRebuilds > before) == (natural > available), "only overflowing titles should start a scroll on activation")
            host.removeFromSuperview()
        }
        let status = StatusLyricMarquee(frame: NSRect(x: 0, y: 0, width: 146, height: 24))
        titleWindow.contentView!.addSubview(status)
        status.setText("A long status-bar lyric that must keep scrolling across layout passes")
        status.setActive(true); status.layout()
        precondition(status.isScrolling, "long status lyric must start scrolling")
        let statusRebuilds = status.animationRebuilds
        for _ in 0..<100 { status.layout() }
        precondition(status.animationRebuilds == statusRebuilds, "status relayout must not restart the scroll")
        status.setText("短句"); status.layout()
        precondition(!status.isScrolling, "short status lyrics must stay still")
        status.setText("第一行\n第二行\r\n第三行"); status.layout()
        precondition(!status.displayedText.contains("\n") && !status.displayedText.contains("\r"), "status text must normalize line breaks")
        precondition(status.layer?.masksToBounds == true, "status glyphs must be clipped to the menu-bar item")
        guard let glyphLayer = status.layer?.sublayers?.first,
              let contents = glyphLayer.contents else { preconditionFailure("status text must render actual glyph pixels") }
        let bitmap = contents as! CGImage
        let pixels = bitmap.dataProvider!.data! as Data
        precondition(pixels.contains { $0 != 0 }, "status glyph bitmap must not be empty")
        precondition(abs(glyphLayer.frame.midY - status.bounds.midY) <= 1, "status lyric line must be vertically centered")
        for eventType in [NSEvent.EventType.leftMouseUp, .rightMouseUp] {
            let event = NSEvent.mouseEvent(with: eventType, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
            precondition(MenuBarLyricsController.opensMenu(for: event) == (eventType == .rightMouseUp), "right click opens menu, left click restores window")
        }
        let controlClick = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: .control, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
        precondition(MenuBarLyricsController.opensMenu(for: controlClick))
        precondition(status.hitTest(NSPoint(x: 10, y: 10)) == nil, "lyric overlay must not intercept status button clicks")
        print("PASS: single-line status glyph bitmap, centered clipped geometry, left/right/control click routing")
        status.removeFromSuperview()
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        let wide = TitleMarquee.MarqueeView(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        titleWindow.contentView!.addSubview(cell); cell.addSubview(wide)
        wide.configure(text: "A long library track title including its final suffix END", active: true); wide.layout()
        let beforeClip = wide.scrollDistance
        cell.setFrameSize(NSSize(width: 60, height: 24)); wide.viewWillDraw()
        precondition(abs(wide.scrollDistance - beforeClip - 40) < 1, "sidebar clipping must increase travel to reveal the full suffix")
        precondition(wide.isScrolling, "resized cell must have a scrolling text layer")
        cell.removeFromSuperview()
        print("PASS: native row sizing, status scroll start and stable relayout, resized cell suffix visibility")
        titleWindow.contentView = nil
        print("PASS: natural-width short titles stay still; constrained long titles scroll")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyPlayer44-" + UUID().uuidString)
        let suite = "MyPlayer.Test44." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = UserDataStore(root: root, defaults: defaults); store.prepare()
        let originals = (0..<32).map { i in Song(path: "/media/\(i).mp3", title: "Song \(i)", artist: "Artist", album: "Album", duration: 20, artworkData: Data(repeating: UInt8(i % 4), count: 512 * 1024)) }
        let originalJSON = try JSONEncoder().encode(originals)
        UserDataFiles.write(originalJSON, to: store.file("library.json")); UserDataFiles.flush()
        let manager = PlayerManager(userData: store, startsServices: false)
        let playbackWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let chrome = ChromeProbe65()
        playbackWindow.contentView = NSHostingView(rootView: PlaybackCanvas65(player: manager, chrome: chrome))
        playbackWindow.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        let interaction = WindowInteraction.InteractionView(frame: .zero)
        playbackWindow.contentView!.addSubview(interaction)
        interaction.onCanvasClick = { _ in chrome.visible.toggle(); return true }
        let regions = CanvasClickPassthrough.regions(in: playbackWindow)
        precondition(!regions.isEmpty, "the actual player bar must register its interactive region")
        let blank = NSPoint(x: 500, y: 400)
        precondition(!CanvasClickPassthrough.contains(blank, in: playbackWindow), "the real bottom bar must not exclude blank playback space: \(regions)")
        precondition(interaction.handleCanvasMouseDown(at: blank, in: playbackWindow) && !chrome.visible, "real player layout must hide on blank clicks")
        try await Task.sleep(for: .milliseconds(50))
        precondition(interaction.handleCanvasMouseDown(at: blank, in: playbackWindow) && chrome.visible, "second blank click must restore real player layout")
        try await Task.sleep(for: .milliseconds(50))
        let bar = CanvasClickPassthrough.regions(in: playbackWindow).first!
        precondition(!interaction.handleCanvasMouseDown(at: NSPoint(x: bar.midX, y: bar.midY), in: playbackWindow), "player bar controls must keep their clicks")
        precondition(interaction.registerPointerMotion(at: NSPoint(x: 10, y: 10)))
        precondition(!interaction.registerPointerMotion(at: NSPoint(x: 10, y: 10)), "layout-generated stationary pointer events must not restore controls")
        playbackWindow.contentView = nil
        print("PASS: actual player bar layout, blank hide/show, control exclusion, stationary motion rejection")
        for _ in 0..<300 {
            if manager.library.allSatisfy({ $0.embeddedArtwork == nil }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        manager.flushLibrarySaves()
        precondition(manager.library.count == originals.count && manager.library.allSatisfy { $0.embeddedArtwork == nil })
        let compact = try Data(contentsOf: store.file("library.json"))
        precondition(compact.count < originalJSON.count / 100)
        let backup = try Data(contentsOf: store.file("library-before-artwork-migration.json"))
        precondition(backup == originalJSON)
        for song in manager.library {
            let original = originals.first { $0.id == song.id }!
            precondition(song.artworkData == original.artworkData, "original bytes must be preserved")
            precondition(song.title == original.title && song.artist == original.artist && song.duration == original.duration)
        }
        let beforeMemory = try childFootprint(store.file("library-before-artwork-migration.json"))
        let afterMemory = try childFootprint(store.file("library.json"))
        precondition(beforeMemory > 0 && afterMemory > 0)
        print("MEASURED: isolated identical-library process footprint: embedded \(beforeMemory) bytes; disk-backed \(afterMemory) bytes")
        let diskFiles = try FileManager.default.contentsOfDirectory(at: store.file("Artwork"), includingPropertiesForKeys: nil)
        precondition(diskFiles.count == 4, "duplicate album artwork must share one file")
        let imported = try JSONDecoder().decode([Song].self, from: compact)
        precondition(imported.allSatisfy { $0.embeddedArtwork == nil && $0.artworkData != nil })
        // A damaged same-size sidecar must not discard an embedded original.
        try Data(repeating: 99, count: 512 * 1024).write(to: diskFiles[0])
        let safeResults = ArtworkStorage.externalize(originals, root: root)
        precondition(safeResults.count == 24)
        print("PASS: artwork metadata \(originalJSON.count) -> \(compact.count) bytes; lossless sidecars, deduplication, preserved backup, corruption protection")

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let table = NSTableView(frame: CGRect(x: 0, y: 0, width: 650, height: 3600))
        // This synthetic 3,600-point document intentionally uses 100 x 36pt
        // rows; production sizing is checked against native SwiftUI above.
        table.rowHeight = 36
        let rows = Rows(); table.dataSource = rows; table.delegate = rows
        table.addTableColumn(NSTableColumn(identifier: .init("track")))
        scroll.documentView = table; window.contentView!.addSubview(scroll)
        table.reloadData(); table.scrollRowToVisible(0); table.layoutSubtreeIfNeeded()
        for i in 0..<10 { _ = table.rowView(atRow: i, makeIfNecessary: true) }
        let anchor = TableTransparency.Anchor(frame: scroll.bounds)
        anchor.selectionTint = .systemRed
        window.contentView!.addSubview(anchor)
        anchor.layout(); try await Task.sleep(for: .milliseconds(30))
        // Offscreen windows have no normal display pass to rebuild rows after
        // native background/grid styling invalidates the initial row cache.
        table.needsLayout = true; table.layoutSubtreeIfNeeded()
        for i in 0..<10 { _ = table.rowView(atRow: i, makeIfNecessary: true) }
        let counts = (0..<10).map { table.rowView(atRow: $0, makeIfNecessary: false)?.subviews.count ?? 0 }
        for i in 0..<200 {
            table.selectRowIndexes(IndexSet(integer: i % 10), byExtendingSelection: false)
            anchor.selectionIDs = [UUID()]
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(30))
        table.needsLayout = true; table.layoutSubtreeIfNeeded()
        for i in 0..<10 { _ = table.rowView(atRow: i, makeIfNecessary: true) }
        anchor.selectionIDs = [UUID()]
        try await Task.sleep(for: .milliseconds(10))
        for i in 0..<10 {
            precondition((table.rowView(atRow: i, makeIfNecessary: false)?.subviews.count ?? 0) == counts[i], "selection must not inject row subviews")
        }
        guard let selectedRow = table.rowView(atRow: 9, makeIfNecessary: false) else {
            preconditionFailure("selected fixture row unavailable: rows=\(table.numberOfRows) visible=\(table.visibleRect) dataSource=\(String(describing: table.dataSource))")
        }
        precondition(selectedRow.backgroundColor == .clear)
        let highlight = selectedRow.layer?.sublayers?.first(where: { $0.name == "MyPlayer.selection" }) as? CAShapeLayer
        precondition(highlight?.fillColor == NSColor.systemRed.withAlphaComponent(0.25).cgColor)
        precondition(highlight?.path?.boundingBox.minX == 8, "selection must leave side margins")
        withExtendedLifetime(rows) {}
        let density = NativeTableDensity(table)
        table.usesAutomaticRowHeights = true; table.rowHeight = 54
        precondition(table.usesAutomaticRowHeights && table.rowHeight == 54, "must not fight SwiftUI property writes through KVO")
        withExtendedLifetime(density) {}
        let marquee = TitleMarquee.MarqueeView(frame: CGRect(x: 0, y: 0, width: 60, height: 20))
        window.contentView!.addSubview(marquee)
        marquee.configure(text: "A long song title that needs to scroll", active: true); marquee.layout()
        let rebuilds = marquee.animationRebuilds
        for _ in 0..<2000 { marquee.configure(text: "A long song title that needs to scroll", active: true); marquee.layout() }
        precondition(marquee.animationRebuilds == rebuilds && rebuilds > 0)
        print("PASS: 200 real table selections without inserted highlight views; no row-height KVO write-back; 2,000 marquee updates without animation restarts")

        var buffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
        let frame = buffer!; CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddressOfPlane(frame, 0), 235, CVPixelBufferGetBytesPerRowOfPlane(frame, 0) * 36)
        memset(CVPixelBufferGetBaseAddressOfPlane(frame, 1), 128, CVPixelBufferGetBytesPerRowOfPlane(frame, 1) * 18)
        CVPixelBufferUnlockBaseAddress(frame, [])
        let palette = VideoFramePalette.sample(frame)!
        precondition(palette.brightness > 0.99 && palette.pixels.count <= 32 * 20 * 4)
        print("PASS: palette samples native NV12 video planes without a full BGRA frame conversion")
    }
}
