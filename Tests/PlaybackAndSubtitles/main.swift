import Foundation

for mode in RepeatMode.allCases {
    precondition(mode.nextAction(manual: true) == .advance)
}
precondition(RepeatMode.playOnce.nextAction(manual: false) == .pause)
precondition(RepeatMode.repeatOne.nextAction(manual: false) == .replay)
precondition(RepeatMode.repeatAll.nextAction(manual: false) == .advance)
let srt = "1\n00:00:01,000 --> 00:00:03,000\nFirst\nline\n\n2\n00:00:04,000 --> 00:00:06,000\n<i>Second</i>\n"
let lines = TimedTextParser.parse(srt)
precondition(lines.count == 2 && lines[0].text == "First line" && lines[1].text == "Second")
precondition(lines[0].time == 1 && lines[0].endTime == 3)
precondition(abs(TimedTextParser.progress(lines: lines, index: 0, time: 2.2, offset: 0.2, duration: 10) - 0.5) < 0.0001)
precondition(TimedTextParser.progress(lines: lines, index: 0, time: 0, offset: 0, duration: 10) == 0)
precondition(TimedTextParser.progress(lines: lines, index: 0, time: 9, offset: 0, duration: 10) == 1)
let vtt = TimedTextParser.parse("WEBVTT\n\n00:01.500 --> 00:03.000 align:start\nHello\n")
precondition(vtt.count == 1 && vtt[0].time == 1.5)
let lrc = TimedTextParser.parse("[00:01.00]One\n[00:03.00]Two")
precondition(lrc.count == 2 && TimedTextParser.progress(lines: lrc, index: 0, time: 2, offset: 0, duration: 10) == 0.5)
precondition(TimedTextParser.parse("1\n00:00:04,000 --> 00:00:01,000\nBad").isEmpty)
for r in stride(from: 0.0, through: 1.0, by: 0.0625) {
    for g in stride(from: 0.0, through: 1.0, by: 0.0625) {
        for b in stride(from: 0.0, through: 1.0, by: 0.0625) {
            let luminance = PlaybackButtonContrast.luminance(r, g, b)
            let contrast = PlaybackButtonContrast.usesBlack(r, g, b) ? (luminance + 0.05) / 0.05 : 1.05 / (luminance + 0.05)
            precondition(contrast >= 4.5)
        }
    }
}
print("PASS: automatic playback policy, manual skip, LRC/SRT/VTT timing, sync offsets, progress bounds and 4,913 accent contrast combinations")
