import AppKit

/// The Appearance menu is declared in SwiftUI. AppKit may still inject a separate
/// View menu for its fullscreen command; hide that duplicate synchronously, before paint.
@MainActor final class AppearanceMenuNaming {
    static let shared = AppearanceMenuNaming()
    private var observers: [NSObjectProtocol] = []
    private var applying = false
    private let menu: () -> NSMenu?
    init(menu: @escaping () -> NSMenu? = { NSApp.mainMenu }) { self.menu = menu }
    func install() {
        guard observers.isEmpty else { apply(); return }
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, note.object as? NSMenu === self.menu() else { return }
                    self.apply()
                }
            })
        }
        apply()
    }
    func apply() {
        guard !applying else { return }; applying = true; defer { applying = false }
        for item in menu()?.items ?? [] where ["View", "显示"].contains(item.title) && !item.isHidden { item.isHidden = true }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
