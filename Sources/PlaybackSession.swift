import Foundation

struct PlaybackSession: Codable, Sendable {
    let songID: UUID
    let path: String
    let seconds: TimeInterval
    let wasPlaying: Bool
    let countedThisPlay: Bool
    let contextIDs: [UUID]?

    func position(limitedTo duration: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return max(0, duration.isFinite && duration > 0 ? min(seconds, duration) : seconds)
    }
}
