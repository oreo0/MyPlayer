import SwiftUI
import AppKit

@MainActor final class ScrollPositionMemory: ObservableObject {
    private var positions: [String: NSPoint] = [:]
    private var pendingScroll: (String, () -> Void)?
    private let anchors = NSHashTable<RetainedScrollPosition.Anchor>.weakObjects()
    @Published private(set) var revision = 0
    func position(for key: String) -> NSPoint? { positions[key] }
    func save(_ point: NSPoint, for key: String) { positions[key] = point }
    func register(_ anchor: RetainedScrollPosition.Anchor) { anchors.add(anchor) }
    func suspend() { pendingScroll = nil; for anchor in anchors.allObjects { anchor.suspend() }; revision += 1 }
    func afterRestoration(of key: String, perform: @escaping () -> Void) {
        pendingScroll = (key, perform); revision += 1
    }
    fileprivate func didRestore(_ key: String) {
        guard let pendingScroll, pendingScroll.0 == key else { return }
        self.pendingScroll = nil; pendingScroll.1()
    }
    func resetToTop(_ key: String) { positions[key] = NSPoint(x: 0, y: -1_000_000); revision += 1 }
}

/// Remembers native scroll offsets without publishing a SwiftUI update per pixel.
struct RetainedScrollPosition: NSViewRepresentable {
    @ObservedObject var memory: ScrollPositionMemory
    let key: String
    let active: Bool
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.configure(memory: memory, key: key, active: active, revision: memory.revision) }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.unbind() }
    final class Anchor: NSView {
        private weak var memory: ScrollPositionMemory?
        private weak var scroll: NSScrollView?
        private var key = ""
        private var active = false
        private var restoring = false
        private var revision = -1
        private var boundsObserver: NSObjectProtocol?
        private var liveScrollObserver: NSObjectProtocol?
        private var settle: DispatchWorkItem?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { schedule() } }
        override func layout() { super.layout(); if scroll == nil && window != nil { schedule() } }
        func configure(memory: ScrollPositionMemory, key: String, active: Bool, revision: Int) {
            let changed = self.memory !== memory || self.key != key || self.active != active || self.revision != revision
            guard changed else { return }
            self.memory = memory; memory.register(self)
            self.key = key; self.active = active; self.revision = revision
            if active { schedule() } else { settle?.cancel(); restoring = false }
        }
        func suspend() {
            if active && !restoring, let scroll { memory?.save(scroll.contentView.bounds.origin, for: key) }
            active = false; settle?.cancel(); restoring = false
        }
        private func resolveScroll() -> NSScrollView? {
            if let enclosingScrollView { return enclosingScrollView }
            guard let root = window?.contentView else { return nil }
            let target = convert(bounds, to: root)
            guard target.width > 0 && target.height > 0 else { return nil }
            var candidates: [(NSScrollView, CGFloat)] = []
            func visit(_ view: NSView) {
                if let candidate = view as? NSScrollView {
                    let rect = candidate.convert(candidate.bounds, to: root)
                    if rect.intersects(target) {
                        candidates.append((candidate, abs(rect.width-target.width) + abs(rect.height-target.height) + abs(rect.minX-target.minX) + abs(rect.minY-target.minY)))
                    }
                }
                for child in view.subviews { visit(child) }
            }
            visit(root)
            return candidates.min(by: { $0.1 < $1.1 })?.0
        }
        private func bindIfNeeded() {
            guard scroll == nil, let found = resolveScroll() else { return }
            scroll = found
            found.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: found.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.active, !self.restoring, let scroll = self.scroll else { return }
                    self.memory?.save(scroll.contentView.bounds.origin, for: self.key)
                }
            }
            liveScrollObserver = NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: found, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.active else { return }
                    self.settle?.cancel(); self.restoring = false
                }
            }
        }
        func schedule() {
            settle?.cancel(); restoring = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active else { return }
                self.bindIfNeeded(); self.restorePosition()
            }
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.active else { return }
                self.bindIfNeeded(); self.restorePosition(); self.restoring = false
                if let scroll = self.scroll { self.memory?.save(scroll.contentView.bounds.origin, for: self.key) }
                self.memory?.didRestore(self.key)
            }
            settle = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }
        func restorePosition() {
            guard active, let scroll else { return }
            let point = memory?.position(for: key) ?? NSPoint(x: 0, y: -1_000_000)
            let clip = scroll.contentView
            let constrained = clip.constrainBoundsRect(NSRect(origin: point, size: clip.bounds.size)).origin
            clip.scroll(to: constrained); scroll.reflectScrolledClipView(clip)
        }
        func unbind() {
            suspend()
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            if let liveScrollObserver { NotificationCenter.default.removeObserver(liveScrollObserver) }
            boundsObserver = nil; liveScrollObserver = nil; scroll = nil
        }
        deinit {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            if let liveScrollObserver { NotificationCenter.default.removeObserver(liveScrollObserver) }
            settle?.cancel()
        }
    }
}
