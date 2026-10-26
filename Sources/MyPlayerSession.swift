import Foundation
import Combine

/// Startup reads the existing local data directory. No cloud service is started.
@MainActor final class MyPlayerSession: ObservableObject {
    @Published private(set) var player: PlayerManager?
    @Published private(set) var collections: CollectionStore?
    private var loading = false
    func load() async {
        guard player == nil, !loading else { return }; loading = true
        defer { loading = false }
        UserDataStore.shared.prepare()
        collections = CollectionStore()
        player = PlayerManager()
    }
}
