import Foundation

enum AppVersion {
    static var version: String {
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        return String(format: "4.0 (%02d)", build)
    }
    static var name: String { "MyPlayer" }
}
