import AppKit
@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
final class FlippedDocument: NSView { override var isFlipped: Bool { true } }
@main struct Navigation19Tests {
    @MainActor static func main() {
        for current in MusicPage.allCases {
            let libraryAction = TabNavigation.action(from: current, to: .library)
            precondition(libraryAction == ((current == .library || current == .favorites) ? .libraryHome : .activate(.library)))
            let collectionsAction = TabNavigation.action(from: current, to: .collections)
            precondition(collectionsAction == (current == .collections ? .collectionsHome : .activate(.collections)))
            precondition(TabNavigation.action(from: current, to: .playing) == .activate(.playing))
        }
        precondition(TabNavigation.action(from: nil, to: .library) == .libraryHome)
        precondition(TabNavigation.action(from: nil, to: .collections) == .activate(.collections))
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        let document = FlippedDocument(frame: .init(x: 0, y: 0, width: 400, height: 2000))
        scroll.documentView = document; window.contentView!.addSubview(scroll)
        let anchor = RetainedScrollPosition.Anchor(frame: .init(x: 0, y: 0, width: 1, height: 1))
        document.addSubview(anchor)
        let memory = ScrollPositionMemory()
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
        func activate(_ key: String) { anchor.configure(memory: memory, key: key, active: true, revision: memory.revision); settle() }
        activate("album:A")
        scroll.contentView.scroll(to: .init(x: 0, y: 1500)); scroll.reflectScrolledClipView(scroll.contentView)
        precondition(memory.position(for: "album:A")?.y == 1500)
        memory.suspend()
        anchor.configure(memory: memory, key: "album:A", active: false, revision: memory.revision)
        let originalSize = scroll.frame.size
        scroll.setFrameSize(.init(width: 400, height: 700))
        scroll.contentView.scroll(to: .init(x: 0, y: 1400))
        precondition(memory.position(for: "album:A")?.y == 1500, "hidden viewport changes must not overwrite saved position")
        scroll.setFrameSize(originalSize)
        activate("album:A")
        precondition(scroll.contentView.bounds.origin.y == 1500)
        memory.suspend(); activate("album:B")
        scroll.contentView.scroll(to: .init(x: 0, y: 700)); scroll.reflectScrolledClipView(scroll.contentView)
        memory.suspend(); activate("album:A")
        precondition(scroll.contentView.bounds.origin.y == 1500)
        memory.suspend(); activate("album:B")
        precondition(scroll.contentView.bounds.origin.y == 700)
        memory.resetToTop("album:B"); activate("album:B")
        precondition(scroll.contentView.bounds.origin.y == 0)
        var located = false
        memory.afterRestoration(of: "album:B") { located = true }
        activate("album:B"); precondition(located)
        memory.resetToTop("album:B")
        anchor.configure(memory: memory, key: "album:B", active: true, revision: memory.revision)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: .init(x: 0, y: 420)); scroll.reflectScrolledClipView(scroll.contentView)
        settle(); precondition(scroll.contentView.bounds.origin.y == 420, "user scrolling cancels pending restoration")
        anchor.unbind()
        print("PASS: native scroll offsets survive hidden viewport changes; independent hierarchy positions, home reset, explicit locate after restoration")
        print("PASS: tab navigation matrix; inactive tabs restore state, repeated active-tab clicks return home")
    }
}
