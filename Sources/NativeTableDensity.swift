import AppKit

/// Apply compact rows before display, then once after SwiftUI's initial layout.
/// No selection observers, repeated timers or KVO writes.
@MainActor
final class NativeTableDensity {
    private weak var table: NSTableView?
    init(_ table: NSTableView) {
        self.table = table
        enforce()
        DispatchQueue.main.async { [weak self] in self?.enforce() }
    }
    func enforce() {
        guard let table else { return }
        var changed = false
        if table.usesAutomaticRowHeights { table.usesAutomaticRowHeights = false; changed = true }
        if table.rowHeight != 36 { table.rowHeight = 36; changed = true }
        if table.intercellSpacing.height != 0 { table.intercellSpacing = NSSize(width: table.intercellSpacing.width, height: 0); changed = true }
        guard changed else { return }
        let visible = table.rows(in: table.visibleRect)
        if visible.location != NSNotFound, visible.length > 0 {
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visible.location..<min(table.numberOfRows, visible.location + visible.length)))
        }
    }
}
