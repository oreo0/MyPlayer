import AppKit
import AVFoundation

/// AVPlayerView pauses on NSWindow.willBeginSheetNotification. Restore only
/// this metadata presentation's previously playing engine after that notification.
@MainActor final class MetadataPlaybackContinuity {
    private var token: NSObjectProtocol?
    init(player: PlayerManager) {
        guard let engine = player.videoPlayer, engine.rate != 0,
              let parent = VideoPresentation.shared.view?.window else { return }
        let rate = engine.rate
        token = NotificationCenter.default.addObserver(forName: NSWindow.willBeginSheetNotification, object: parent, queue: .main) { [weak self, weak player, weak engine] _ in
            MainActor.assumeIsolated {
                self?.invalidate()
                if let player, let engine, InteractionActivity.shared.isEditingMetadata {
                    player.resumeAfterMetadataSheet(engine: engine, rate: rate)
                }
            }
            DispatchQueue.main.async {
                guard let player, let engine, InteractionActivity.shared.isEditingMetadata else { return }
                player.resumeAfterMetadataSheet(engine: engine, rate: rate)
            }
        }
    }
    func invalidate() { if let token { NotificationCenter.default.removeObserver(token); self.token = nil } }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
