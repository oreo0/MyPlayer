import AppKit
import UniformTypeIdentifiers

@MainActor enum FileDropImporter {
    static func receive(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) -> Bool {
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !accepted.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in accepted {
                let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                        let url: URL?
                        if let item = value as? URL { url = item }
                        else if let data = value as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                        else if let text = value as? String { url = URL(string: text) }
                        else { url = nil }
                        continuation.resume(returning: url?.isFileURL == true ? url : nil)
                    }
                }
                if let url, !urls.contains(url) { urls.append(url) }
            }
            if !urls.isEmpty { completion(urls) }
        }
        return true
    }
}
