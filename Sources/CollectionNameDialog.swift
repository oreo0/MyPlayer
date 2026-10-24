import SwiftUI
import AppKit

/// Present the system's current dialog, rather than drawing a sheet imitation.
@MainActor
enum CollectionNameDialog {
    static func present(title: String, saveTitle: String, name: String, onSave: @escaping (String) -> Void) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "请输入合集名称。"
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: saveTitle)
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: name)
        field.placeholderString = "合集名称"
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 26)
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .alertFirstButtonReturn && !value.isEmpty { onSave(value) }
        }
    }
}

struct PageHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: 32, weight: .black))
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// Size the symbol itself, not a forced button box or a parent menu's font.
struct ToolbarGlyph: View {
    let symbol: String
    let title: String
    var body: some View {
        Label(title, systemImage: symbol).labelStyle(.iconOnly)
    }
}
