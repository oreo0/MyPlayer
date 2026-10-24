import Foundation
import Combine

/// Deliver line boundaries, including the initial paused position and seeks.
/// The lyric list does not subscribe to every progress tick as view state.
enum LyricProgress {
    static func indices<P: Publisher>(times: P, lyrics: [LyricLine], offset: TimeInterval = 0) -> AnyPublisher<Int?, Never>
    where P.Output == TimeInterval, P.Failure == Never {
        times.map { time in
            LRCParser.currentIndex(for: lyrics, at: time - offset) ?? (lyrics.isEmpty ? nil : 0)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
