import SwiftUI

/// Focus changes in either retained browser must not rebuild ContentView and
/// feed another toolbar/focus preference update back into that browser.
struct CollectionToolbarControls: View {
    enum Kind { case play, management }
    let kind: Kind
    @FocusedValue(\.collectionActions) private var actions
    var body: some View {
        switch kind {
        case .play:
            Button("播放全部", systemImage: "play.fill") { actions?.play() }
                .disabled(actions?.canPlay != true)
        case .management:
            ControlGroup {
                Button { actions?.create() } label: { ToolbarGlyph(symbol: "plus", title: "新建合集") }.help("新建合集")
                Menu {
                    Button("重命名合集…", systemImage: "pencil") { actions?.rename() }
                    Button("删除合集", systemImage: "trash", role: .destructive) { actions?.delete() }
                } label: { ToolbarGlyph(symbol: "ellipsis.circle", title: "合集管理") }
                    .help("合集管理")
                    .disabled(actions?.hasSelection != true)
            }.controlGroupStyle(.navigation)
        }
    }
}
