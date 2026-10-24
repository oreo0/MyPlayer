import SwiftUI
import AppKit
import CoreImage

/// SwiftUI Table can leave the underlying AppKit scroll view opaque even after
/// scrollContentBackground(.hidden). Clear the retained tab tables under this
/// anchor; hidden tabs can occupy the same frame as the visible table.
struct TableTransparency: NSViewRepresentable {
    @Environment(\.playbackAccent) private var playbackAccent
    private var selectionTint: NSColor { NSColor(playbackAccent ?? ThemeColor.current.color ?? Color(nsColor: .controlAccentColor)).usingColorSpace(.deviceRGB) ?? .controlAccentColor }
    var bottomInset: CGFloat = 0
    var scrollingHeaderHeight: CGFloat = 0
    var selectionOnly = false
    var selectionIDs = Set<UUID>()
    var locateRow: Int?
    var locateRequest: UUID?
    func makeNSView(context: Context) -> Anchor { let view = Anchor(); view.bottomInset = bottomInset; view.scrollingHeaderHeight = scrollingHeaderHeight; view.selectionOnly = selectionOnly; view.selectionIDs = selectionIDs; view.selectionTint = selectionTint; return view }
    func updateNSView(_ view: Anchor, context: Context) { view.bottomInset = bottomInset; view.scrollingHeaderHeight = scrollingHeaderHeight; view.selectionOnly = selectionOnly; view.selectionIDs = selectionIDs; view.selectionTint = selectionTint; view.locateRow = locateRow; view.locateRequest = locateRequest; view.schedule() }
    final class Anchor: NSView {
        var selectionTint: NSColor = .controlAccentColor {
            didSet { if selectionTint != oldValue { refreshKnownSelections() } }
        }
        var scrollingHeaderHeight: CGFloat = 0
        var selectionOnly = false
        var selectionIDs = Set<UUID>() { didSet { if oldValue != selectionIDs { refreshKnownSelections() } } }
        private var selectionObservers: [NSObjectProtocol] = []
        var locateRow: Int?
        var locateRequest: UUID? { didSet { if oldValue != locateRequest { needsUpdate = true } } }
        private var handledLocateRequest: UUID?
        private var needsUpdate = true
        var bottomInset: CGFloat = 0 { didSet { if bottomInset != oldValue { needsUpdate = true; schedule() } } }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            selectionObservers.forEach(NotificationCenter.default.removeObserver)
            selectionObservers.removeAll()
            guard window != nil else { densities.removeAll(); return }
            selectionObservers.append(NotificationCenter.default.addObserver(forName: NSTableView.selectionDidChangeNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let table = note.object as? NSTableView,
                          self.tables.contains(where: { $0.value === table }) else { return }
                    self.requestSelectionRefresh(in: table)
                }
            })
            selectionObservers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let clip = note.object as? NSClipView else { return }
                    for table in self.tables.compactMap({ $0.value }) where table.enclosingScrollView?.contentView === clip {
                        self.requestSelectionRefresh(in: table)
                    }
                }
            })
            schedule()
        }
        override func layout() { super.layout(); updateScrollChrome(); schedule() }
        private func updateScrollChrome() {
            for table in tables.compactMap({ $0.value }) {
                if !table.gridStyleMask.isEmpty { table.gridStyleMask = [] }
                guard !selectionOnly, let scroll = table.enclosingScrollView else { continue }
                if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
                if scroll.horizontalScroller?.isHidden == false { scroll.horizontalScroller?.isHidden = true }
                if scroll.contentView.bounds.origin.x != 0 {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
                }
            }
        }
        private var pending = false
        private var tables: [WeakTable] = []
        private var densities: [ObjectIdentifier: NativeTableDensity] = [:]
        private struct WeakTable { weak var value: NSTableView? }
        func schedule() {
            guard !pending else { return }
            tables.removeAll { $0.value?.window !== window || $0.value == nil }
            let living = Set(tables.compactMap { $0.value.map(ObjectIdentifier.init) })
            densities = densities.filter { living.contains($0.key) }
            guard tables.isEmpty || needsUpdate else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                self.clearTable()
            }
        }
        private func clearTable() {
            guard let root = window?.contentView, bounds.width > 0 else { return }
            let target = convert(bounds, to: root)
            var matches: [(NSTableView, CGFloat)] = []
            func visit(_ view: NSView) {
                if let table = view as? NSTableView {
                    let overlap = root.convert(table.bounds, from: table).intersection(target)
                    if !overlap.isNull && overlap.width > 0 && overlap.height > 0 { matches.append((table, overlap.width * overlap.height)) }
                }
                for child in view.subviews { visit(child) }
            }
            func distance(to table: NSTableView) -> Int {
                var ancestor = superview
                var result = 0
                while let view = ancestor {
                    if table.isDescendant(of: view) { return result }
                    ancestor = view.superview; result += 1
                }
                return Int.max
            }
            if tables.isEmpty {
                visit(root)
                if let nearest = matches.map({ distance(to: $0.0) }).min() {
                    matches = matches.filter { distance(to: $0.0) == nearest }
                }
                tables = matches.map { WeakTable(value: $0.0) }
            } else { matches = tables.compactMap { $0.value.map { ($0, CGFloat(0)) } } }
            if let request = locateRequest, request != handledLocateRequest, let row = locateRow {
                // The retained tabs overlap. Locate only the table sharing the
                // nearest view ancestor with this anchor, preserving other tabs.
                if let table = matches.min(by: { distance(to: $0.0) < distance(to: $1.0) })?.0,
                   row >= 0 && row < table.numberOfRows {
                    table.scrollRowToVisible(row)
                    handledLocateRequest = request
                }
            }
            needsUpdate = false
            for (table, _) in matches {
                // Grid style only: never set gridColor or row separator colors
                // (those trigger the macOS 27 SwiftUI row initialization crash).
                if !table.gridStyleMask.isEmpty { table.gridStyleMask = [] }
                if selectionOnly { refreshSelection(in: table); continue }
                refreshSelection(in: table)
                if table.columnAutoresizingStyle != .uniformColumnAutoresizingStyle { table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle }
                if let scroll = table.enclosingScrollView {
                    if !scroll.contentView.postsBoundsChangedNotifications { scroll.contentView.postsBoundsChangedNotifications = true }
                    if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
                    if scroll.horizontalScrollElasticity != .none { scroll.horizontalScrollElasticity = .none }
                    // Let AppKit update the top inset after the native toolbar finishes
                    // its first layout. Freezing it here can pin the table header
                    // underneath the toolbar on a freshly restored window.
                    if !scroll.automaticallyAdjustsContentInsets { scroll.automaticallyAdjustsContentInsets = true }
                    if abs(scroll.contentInsets.bottom - bottomInset) > 0.5 {
                    var insets = scroll.contentInsets
                    insets.bottom = bottomInset
                    scroll.contentInsets = insets
                    }
                }
                if table.backgroundColor != .clear { table.backgroundColor = .clear }
                if table.usesAlternatingRowBackgroundColors { table.usesAlternatingRowBackgroundColors = false }
                if table.enclosingScrollView?.drawsBackground == true { table.enclosingScrollView?.drawsBackground = false }
                if table.enclosingScrollView?.contentView.drawsBackground == true { table.enclosingScrollView?.contentView.drawsBackground = false }
            }
        }
        private var pendingSelection = Set<ObjectIdentifier>()
        private func requestSelectionRefresh(in table: NSTableView) {
            let id = ObjectIdentifier(table)
            guard pendingSelection.insert(id).inserted else { return }
            DispatchQueue.main.async { [weak self, weak table] in
                guard let self else { return }
                self.pendingSelection.remove(id)
                if let table { self.refreshSelection(in: table) }
            }
        }
        private func refreshKnownSelections() {
            for table in tables.compactMap({ $0.value }) { requestSelectionRefresh(in: table) }
        }
        private func refreshSelection(in table: NSTableView) {
            if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
            // The system focus ring can otherwise encompass the entire retained table.
            if table.focusRingType != .none { table.focusRingType = .none }
            if let scroll = table.enclosingScrollView, scroll.focusRingType != .none { scroll.focusRingType = .none }
            if let clip = table.enclosingScrollView?.contentView, !clip.postsBoundsChangedNotifications { clip.postsBoundsChangedNotifications = true }
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound, visible.length > 0 else { return }
            let selectedColor = selectionTint.withAlphaComponent(0.25)
            for row in visible.location..<min(table.numberOfRows, visible.location + visible.length) {
                guard let rowView = table.rowView(atRow: row, makeIfNecessary: false) else { continue }
                // One retained backing layer per visible native row, no hosted
                // views or full-table redraws when selection changes.
                if !rowView.wantsLayer { rowView.wantsLayer = true }
                guard let backing = rowView.layer else { continue }
                if backing.masksToBounds { backing.masksToBounds = false }
                let highlight: CAShapeLayer
                if let existing = backing.sublayers?.first(where: { $0.name == "MyPlayer.selection" }) as? CAShapeLayer {
                    highlight = existing
                } else {
                    highlight = CAShapeLayer(); highlight.name = "MyPlayer.selection"
                    backing.insertSublayer(highlight, at: 0)
                }
                let rect = rowView.bounds.insetBy(dx: 8, dy: 2)
                let radius = SurfaceCorners.selectionRadius(height: rect.height)
                let desired = table.selectedRowIndexes.contains(row) ? selectedColor : NSColor.clear
                CATransaction.begin(); CATransaction.setDisableActions(true)
                if highlight.frame != rowView.bounds || highlight.path == nil {
                    highlight.frame = rowView.bounds
                    highlight.path = CGPath(roundedRect: CGRect(origin: .zero, size: rect.size).offsetBy(dx: 8, dy: 2), cornerWidth: radius, cornerHeight: radius, transform: nil)
                }
                if highlight.fillColor != desired.cgColor { highlight.fillColor = desired.cgColor }
                // Keep the retained selection layer in the same content-only
                // blur as its row. Never add a material over the window backdrop.
                let rowRect = convert(rowView.bounds, from: rowView)
                let rowTop = isFlipped ? rowRect.minY : bounds.maxY - rowRect.maxY
                let blurRadius = scrollingHeaderHeight > 0 && table.selectedRowIndexes.contains(row)
                    ? min(18, max(0, (scrollingHeaderHeight - rowTop) * 0.5)) : 0
                let previousBlur = (highlight.filters?.first as? CIFilter)?.value(forKey: kCIInputRadiusKey) as? CGFloat ?? 0
                if abs(previousBlur - blurRadius) > 0.01 {
                    highlight.filters = blurRadius > 0
                        ? CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius]).map { [$0] } : nil
                }

                if rowView.backgroundColor != .clear { rowView.backgroundColor = .clear }
                CATransaction.commit()
            }
        }
        deinit { selectionObservers.forEach(NotificationCenter.default.removeObserver) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

