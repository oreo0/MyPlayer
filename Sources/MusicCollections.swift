import SwiftUI

struct AddToCollectionMenu: View {
    @EnvironmentObject private var store: CollectionStore
    let ids: [UUID]
    var create: () -> Void = {}
    var body: some View {
        Menu("添加到合集", systemImage: "text.badge.plus") {
            ForEach(store.collections) { collection in
                Button(collection.name) { store.add(ids, to: collection.id) }
            }
            Divider()
            Button("新建合集…", action: create)
        }
    }
}

struct CollectionToolbarActions {
    var create: () -> Void
    var play: () -> Void
    var rename: () -> Void
    var delete: () -> Void
    var canPlay: Bool
    var hasSelection: Bool
}
private struct CollectionActionsKey: FocusedValueKey { typealias Value = CollectionToolbarActions }
extension FocusedValues {
    var collectionActions: CollectionToolbarActions? {
        get { self[CollectionActionsKey.self] }
        set { self[CollectionActionsKey.self] = newValue }
    }
}

struct CollectionsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var store: CollectionStore
    let isActive: Bool
    let bottomClearance: CGFloat
    @AppStorage("collectionSidebarPreferredWidth") private var savedSidebarWidth = 200.0
    @State private var sidebarWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 800
    @State private var selected: UUID?
    @State private var toolbarActions: CollectionToolbarActions?
    @State private var highlightedSong: UUID?
    @State private var editingSong: Song?
    @State private var missingCurrent = false
    @State private var editing = false
    @State private var renaming = false
    @State private var name = ""
    @State private var pendingCreateIDs: [UUID] = []
    private var collection: MusicCollection? { store.collections.first { $0.id == selected } }
    var body: some View {
        ScrollViewReader { proxy in
        HStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(store.collections) { item in
                        Label(item.name, systemImage: "rectangle.stack").tag(item.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: MediaRowMetrics.contentHeight)
                            .modifier(CollectionHeaderBlur())
                            .listRowInsets(MediaRowMetrics.insets)
                            .listRowSeparator(.hidden)
                            .contextMenu {
                                Section("播放") {
                                    Button("播放整个合集") { player.playCollection(player.songs(for: item.songIDs)) }.disabled(item.songIDs.isEmpty)
                                }
                                Section("管理") { Button("重命名合集…") { selected = item.id; beginRename(item) } }
                                Section("移除") { Button("删除合集", role: .destructive) { store.confirmDelete(item.id) } }
                            }
                    }
                }
                .modifier(CollectionListSurface(bottomClearance: bottomClearance))
                .safeAreaInset(edge: .top, spacing: 0) {
                    CollectionPanelHeading(title: "我的合集").padding(.bottom, 24)
                }
                .frame(width: CollectionSidebarMetrics.width(available: availableWidth, preferred: sidebarWidth > 0 ? sidebarWidth : savedSidebarWidth))
                .accessibilityIdentifier("collections.sidebar")
            PanelResizeHandle(width: Binding(
                get: { CollectionSidebarMetrics.width(available: availableWidth, preferred: sidebarWidth > 0 ? sidebarWidth : savedSidebarWidth) },
                set: { sidebarWidth = $0 }),
                limits: CollectionSidebarMetrics.limits(available: availableWidth),
                onEnd: { savedSidebarWidth = Double(sidebarWidth > 0 ? sidebarWidth : savedSidebarWidth) }, growsRight: true)
                .overlay { Divider().allowsHitTesting(false) }
                .accessibilityIdentifier("collections.resize")
            VStack(spacing: 0) {
                if let collection {
                    let songs = player.songs(for: collection.songIDs)
                    List {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            HStack {
                                Text("\(index + 1)").monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(.secondary).frame(width: MediaRowMetrics.numberWidth(count: songs.count))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.title).lineLimit(1).frame(height: 20, alignment: .leading)
                                    Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height: 16, alignment: .leading)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Spacer()
                                Text(formatTime(song.duration)).font(.caption).monospacedDigit().lineLimit(1).fixedSize()
                                Button { store.confirmRemove(song.id, from: collection.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("从合集移除")
                            }
                            .id(song.id)
                            .contextMenu {
                                MediaContextMenu(song: song, play: { player.playCollection(songs, startingAt: song.id) }, edit: { editingSong = song }, createCollection: { beginCreate(with: [song.id]) }, removalTitle: "从合集移除", remove: { store.confirmRemove(song.id, from: collection.id) })
                            }
                            .frame(height: MediaRowMetrics.contentHeight)
                            .modifier(CollectionHeaderBlur())
                            .listRowInsets(MediaRowMetrics.insets)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { player.playCollection(songs, startingAt: song.id) }
                            // Recognize selection alongside double-click playback,
                            // without waiting for the double-click interval.
                            .simultaneousGesture(TapGesture().onEnded { highlightedSong = song.id })
                            .listRowBackground(RoundedRectangle(cornerRadius: SurfaceCorners.selectionRadius(height: MediaRowMetrics.contentHeight), style: .continuous)
                                .fill(highlightedSong == song.id ? Color.accentColor.opacity(0.22) : .clear)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .modifier(CollectionHeaderBlur()))
                        }
                    }
                    .modifier(CollectionListSurface(bottomClearance: bottomClearance))
                    .overlay { if songs.isEmpty { ContentUnavailableView("合集暂无文件", systemImage: "music.note.list", description: Text("在资料库中右键文件，选择“添加到合集”")) } }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        CollectionPanelHeading(title: collection.name, subtitle: "\(songs.count) 个文件").padding(.bottom, 24)
                    }
                    .accessibilityIdentifier("collections.tracks")
                } else {
                    ContentUnavailableView("选择或创建合集", systemImage: "rectangle.stack", description: Text("使用顶栏的加号创建合集"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(name: CollectionHeaderBlur.coordinateSpace)
        .clipped()
        .onReceive(NotificationCenter.default.publisher(for: .locateCurrentMedia)) { _ in
            guard isActive, let song = player.nowPlaying else { return }
            let target = collection?.songIDs.contains(song.id) == true ? collection : store.collections.first { $0.songIDs.contains(song.id) }
            guard let target else { missingCurrent = true; return }
            selected = target.id
            highlightedSong = song.id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard selected == target.id, highlightedSong == song.id else { return }
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(song.id, anchor: .center) }
            }
        }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { availableWidth = $0 }
        .clipped()
        .background(TableTransparency(scrollingHeaderHeight: CollectionHeaderBlur.headingInset, selectionOnly: true, selectionIDs: Set([selected, highlightedSong].compactMap { $0 })))
        .focusedSceneValue(\.collectionActions, isActive ? toolbarActions : nil)
        .onAppear { updateToolbarActions() }
        .onChange(of: selected) { _, _ in updateToolbarActions() }
        .onChange(of: store.collections) { _, _ in updateToolbarActions() }
        .onChange(of: player.library.count) { _, _ in updateToolbarActions() }
        .sheet(item: $editingSong) { MediaInfoEditor(song: $0).environmentObject(player) }
        .nativeDialog("当前播放的文件尚未加入任何合集", isPresented: $missingCurrent)
        .onChange(of: editing) { _, presented in
            guard presented else { return }; editing = false
            CollectionNameDialog.present(title: renaming ? "重命名合集" : "新建合集", saveTitle: "保存", name: name) { value in
                if renaming, let selected { store.rename(selected, to: value) }
                else { selected = store.create(value, songs: pendingCreateIDs) }
            }
        }
    }
    private func updateToolbarActions() {
        let current = collection
        toolbarActions = CollectionToolbarActions(
            create: { beginCreate() },
            play: { if let current { player.playCollection(player.songs(for: current.songIDs)) } },
            rename: { if let current { beginRename(current) } },
            delete: { if let current { store.confirmDelete(current.id) } },
            canPlay: current.map { !player.songs(for: $0.songIDs).isEmpty } ?? false,
            hasSelection: current != nil)
    }
    private func beginCreate(with ids: [UUID] = []) { renaming = false; name = ""; pendingCreateIDs = ids; editing = true }
    private func beginRename(_ item: MusicCollection) { renaming = true; name = item.name; editing = true }
}

/// Both native lists share row and scroll geometry, including their header inset.
private struct CollectionListSurface: ViewModifier {
    let bottomClearance: CGFloat
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, MediaRowMetrics.contentHeight + MediaRowMetrics.insets.top + MediaRowMetrics.insets.bottom)
            .scrollContentBackground(.hidden)
            .scrollClipDisabled(false)
            .contentMargins(.bottom, bottomClearance, for: .scrollContent)
    }
}

/// Transparent headings share the unmodified window backdrop.
private struct CollectionPanelHeading: View {
    static let height: CGFloat = 72
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PageHeading(title).lineLimit(1)
            Text(subtitle ?? " ").font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(subtitle == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .zIndex(1)
    }
}

/// Persist the user's width, while temporarily clamping for narrower windows.
enum CollectionSidebarMetrics {
    static func limits(available: CGFloat) -> ClosedRange<CGFloat> {
        let maximum = max(160, min(420, available - 232))
        return 160...maximum
    }
    static func width(available: CGFloat, preferred: CGFloat) -> CGFloat {
        let bounds = limits(available: available)
        return min(bounds.upperBound, max(bounds.lowerBound, preferred.isFinite ? preferred : 200))
    }
}
