import Foundation
import Combine

final class Clock { @Published var time: TimeInterval = 0 }
let clock = Clock()
let lines = LRCParser.parse("[00:01]first\n[00:03]second\n[00:05]third")
var received: [Int?] = []
let subscription = LyricProgress.indices(times: clock.$time, lyrics: lines).sink { received.append($0) }
precondition(received == [0])
for time in [0.1, 1, 1.5, 2.99, 3, 3.1, 5, 7, 1, 0] { clock.time = time }
precondition(received == [0, 1, 2, 0])
subscription.cancel()
clock.time = 5
var resumed: Int??
let replacement = LyricProgress.indices(times: clock.$time, lyrics: lines).sink { resumed = .some($0) }
precondition(resumed! == 2)
var empty: Int??
let emptySubscription = LyricProgress.indices(times: clock.$time, lyrics: []).sink { empty = .some($0) }
precondition(empty != nil && empty! == nil)
print("PASS: initial position, line boundaries, duplicate ticks, backwards seeks, recreated lyric views, empty lyrics")
