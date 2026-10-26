import Foundation
import AudioToolbox

/// Core Audio exposes Vorbis comments and pictures that AVAsset.commonMetadata omits for FLAC.
enum AudioFileMetadata {
    static func read(_ url: URL) -> SourceMediaMetadata? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return nil }
        defer { AudioFileClose(file) }
        var raw: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout.size(ofValue: raw))
        let status = withUnsafeMutablePointer(to: &raw) { AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, $0) }
        let dictionary = raw?.takeRetainedValue() as? [String: Any] ?? [:]
        guard status == noErr else { return nil }
        var picture: Unmanaged<CFData>?
        size = UInt32(MemoryLayout.size(ofValue: picture))
        _ = withUnsafeMutablePointer(to: &picture) { AudioFileGetProperty(file, kAudioFilePropertyAlbumArtwork, &size, $0) }
        let artwork = picture?.takeRetainedValue() as Data?
        return SourceMediaMetadata(title: dictionary["title"] as? String ?? "", artist: dictionary["artist"] as? String ?? "", album: dictionary["album"] as? String ?? "", artwork: artwork)
    }
}
