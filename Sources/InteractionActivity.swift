import AppKit
import Combine

/// Hold presentation geometry while a native menu or metadata sheet owns input.
@MainActor final class InteractionActivity: ObservableObject {
    static let shared = InteractionActivity()
    @Published private(set) var isTrackingMenu = false
    @Published private(set) var isEditingMetadata = false
    var holdsAutoHide: Bool { isTrackingMenu || isEditingMetadata }
    private var menus = Set<ObjectIdentifier>()
    private var editors = Set<UUID>()
    private var tokens: [NSObjectProtocol] = []
    init(observesMenus: Bool = true) {
        guard observesMenus else { return }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let menu = event.object as? NSMenu else { return }
                    self?.track(menu, began: event.name == NSMenu.didBeginTrackingNotification)
                }
            })
        }
    }
    func track(_ menu: NSMenu, began: Bool) {
        if began { menus.insert(ObjectIdentifier(menu)) } else { menus.remove(ObjectIdentifier(menu)) }
        let next = !menus.isEmpty
        if next != isTrackingMenu { isTrackingMenu = next }
    }
    func editing(_ id: UUID, began: Bool) {
        if began { editors.insert(id) } else { editors.remove(id) }
        let next = !editors.isEmpty
        if next != isEditingMetadata { isEditingMetadata = next; MetadataShortcutScope.shared.set(next) }
    }
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}

@MainActor enum PlaybackKeyboardScope {
    static func permitsTransport(in window: NSWindow?, activity: InteractionActivity = .shared) -> Bool {
        guard !activity.isEditingMetadata, !activity.isTrackingMenu,
              NSApp.modalWindow == nil, let window, window.attachedSheet == nil,
              window.sheetParent == nil else { return false }
        if window.firstResponder is NSTextView || window.firstResponder is NSSlider || window.firstResponder is NSTextField { return false }
        return true
    }
}

/// Transport shortcuts observe only editor changes, never menu tracking itself.
@MainActor final class MetadataShortcutScope: ObservableObject {
    static let shared = MetadataShortcutScope()
    @Published private(set) var isEditing = false
    func set(_ value: Bool) { if value != isEditing { isEditing = value } }
}

/// Native menu contents are a snapshot until tracking ends; coalesce model changes.
@MainActor final class MenuPlayerObserver: ObservableObject {
    let player: PlayerManager
    private let activity: InteractionActivity
    private var pending = false
    private var tokens: [AnyCancellable] = []
    init(player: PlayerManager, activity: InteractionActivity = .shared) {
        self.player = player; self.activity = activity
        player.objectWillChange.sink { [weak self] in
            guard let self else { return }
            if self.activity.isTrackingMenu { self.pending = true }
            else { self.objectWillChange.send() }
        }.store(in: &tokens)
        activity.$isTrackingMenu.dropFirst().sink { [weak self] tracking in
            guard !tracking, let self, self.pending else { return }
            self.pending = false
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }.store(in: &tokens)
    }
}
