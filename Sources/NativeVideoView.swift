import SwiftUI
import AVKit

/// One native video surface, shared by the custom controls and menu commands.
@MainActor
final class VideoPresentation: NSObject, ObservableObject, AVPlayerViewPictureInPictureDelegate {
    @Published private(set) var isPictureInPicture = false
    func playerViewDidStartPicture(inPicture playerView: AVPlayerView) { isPictureInPicture = true }
    func playerViewDidStopPicture(inPicture playerView: AVPlayerView) { isPictureInPicture = false }
    static let shared = VideoPresentation()
    weak var view: AVPlayerView?
    func toggleFullScreen() { view?.window?.toggleFullScreen(nil) }
    func togglePictureInPicture() {
        // AVKit on macOS exposes no public programmatic PiP action. Use its
        // existing native button action only when this OS implements it.
        let action = NSSelectorFromString("pictureInPictureButtonTapped:")
        guard let view, view.responds(to: action) else { return }
        view.perform(action, with: nil)
    }
    func playerViewShouldAutomaticallyDismissAtPicture(inPictureStart playerView: AVPlayerView) -> Bool { false }
}

struct NativeVideoView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.updatesNowPlayingInfoCenter = false
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = true
        view.pictureInPictureDelegate = VideoPresentation.shared
        view.videoGravity = .resizeAspect
        view.player = player
        VideoPresentation.shared.view = view
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        VideoPresentation.shared.view = view
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        if VideoPresentation.shared.view === view { VideoPresentation.shared.view = nil }
        view.player = nil
    }
}
