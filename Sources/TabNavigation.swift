import Foundation

/// A repeated click is a home shortcut; entering another tab restores its state.
enum TabNavigation {
    enum Action: Equatable {
        case activate(MusicPage)
        case libraryHome
        case collectionsHome
    }
    static func action(from current: MusicPage?, to target: MusicPage) -> Action {
        if target == .library && (current == .library || current == .favorites || current == nil) { return .libraryHome }
        if target == .collections && current == .collections { return .collectionsHome }
        return .activate(target)
    }
}
extension Notification.Name {
    static let libraryHome = Notification.Name("MyPlayer.libraryHome")
    static let collectionsHome = Notification.Name("MyPlayer.collectionsHome")
}
