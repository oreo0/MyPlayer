import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@MainActor enum RenderProbe24 { static var count = 0; static func tick() { count += 1 } }
@MainActor final class FocusModel24: ObservableObject {
    @Published var step = 0
    var actions: CollectionToolbarActions {
        CollectionToolbarActions(create: {}, play: {}, rename: {}, delete: {}, canPlay: step % 2 == 0, hasSelection: step % 3 == 0)
    }
}
struct FocusInput24: View {
    @ObservedObject var focus: FocusModel24
    var body: some View {
        TextField("Focus probe", text: .constant("focus"))
            .frame(width: 80).focusedSceneValue(\.collectionActions, focus.actions)
    }
}
struct FocusHarness24: View {
    let focus: FocusModel24
    let player: PlayerManager
    let collections: CollectionStore
    var body: some View {
        HStack {
            FocusInput24(focus: focus)
            ContentView().environmentObject(player).environmentObject(collections)
        }
    }
}
@main struct Test24 {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.set(false, forKey: "showMenuBarLyrics")
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let defaults = UserDefaults(suiteName: "MyPlayer.Focus24." + UUID().uuidString)!
        defaults.set(false, forKey: "showMenuBarLyrics"); defaults.set(false, forKey: "autoScanFolders")
        let store = UserDataStore(root: root.appendingPathComponent("data"), defaults: defaults); store.prepare()
        let player = PlayerManager(userData: store, startsServices: false), collections = CollectionStore(url: store.file("collections.json")), focus = FocusModel24()
        let host = NSHostingView(rootView: FocusHarness24(focus: focus, player: player, collections: collections).defaultAppStorage(defaults))
        let window = NSWindow(contentRect: .init(x: -4000, y: -4000, width: 1240, height: 780), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        func fields(_ view: NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields) }
        guard let field = fields(host).first(where: { $0.stringValue == "focus" }) else { fatalError("focus probe missing") }
        window.makeFirstResponder(field); try await Task.sleep(for: .milliseconds(300))
        RenderProbe24.count = 0
        for step in 1...40 { focus.step = step; try await Task.sleep(for: .milliseconds(35)) }
        let renders = RenderProbe24.count
        print("FOCUS_ROOT_RENDERS", renders)
        if CommandLine.arguments.contains("--baseline") { guard renders > 10 else { fatalError("baseline must demonstrate focus-to-root invalidation") } }
        else { guard renders <= 2 else { fatalError("focus changes rebuild whole ContentView: \(renders)") } }
        player.stop(); window.contentView = nil
        print("PASS: focus invalidation measurement completed with isolated data")
    }
}
