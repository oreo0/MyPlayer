import Foundation

enum AppVersion {
    static var version: String {
        "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0.24")
    }
    static var name: String { "MyPlayer" }
}
