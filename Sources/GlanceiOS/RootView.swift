//
//  RootView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.access {
            case .unknown:
                ProgressView()
            case .denied:
                AccessDeniedView()
            case .ready:
                ViewerScreen()
            }
        }
        .task { await store.start() }
        // Returning from Settings after granting access.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.access != .ready { store.refreshAccess() }
        }
    }
}

struct AccessDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("需要访问照片", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("“过目”需要读取你的相册，才能帮你快速筛选照片。照片只在本机处理，不会上传。")
        } actions: {
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// The only screen: the photo fills the display. Rating is a swipe on the photo itself
/// (up = keep, down = discard) *and* a visible glass dock; left / right turns the page.
/// Every control floats over the photo on Liquid Glass so it stays readable on any picture.
struct ViewerScreen: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct CompareRequest: Identifiable {
        let id = UUID()
        let assetIDs: [String]
    }

    enum GridMode: String, Identifiable {
        case browse, pickForCompare
        var id: String { rawValue }
    }

    @State private var chromeVisible = true
    @State private var dragProgress: CGFloat = 0
    @State private var toast: LibraryStore.RatingEvent?
    @State private var gridMode: GridMode?
    @State private var compareRequest: CompareRequest?
    @State private var confirmCleanup = false
    @State private var confirmDeleteCurrent = false
    @AppStorage("autoAdvance") private var autoAdvance = true
    @AppStorage("didShowGestureGuide") private var didShowGuide = false
    @State private var showGuide = false

    private var currentStatus: ImageStatus {
        store.currentID.map { metadata.getMetadata(forKey: $0).status } ?? .undecided
    }

    var body: some View {
        ZStack {
            GlancePalette.canvas(scheme).ignoresSafeArea()

            if store.visible.isEmpty {
                EmptyFilterView()
            } else {
                ViewerPager(
                    onSingleTap: { toggleChrome() },
                    onVerticalProgress: { dragProgress = $0 },
                    onVerticalCommit: { direction in commit(direction == 1 ? .keep : .discard) }
                )
                .ignoresSafeArea()
            }

            ratingBadge
            dragHUD

            VStack(spacing: 10) {
                topControls
                Spacer(minLength: 0)
                toastView
                ratingDock
            }
            .padding(.bottom, 6)
            .opacity(chromeVisible || store.visible.isEmpty ? 1 : 0)
            .allowsHitTesting(chromeVisible || store.visible.isEmpty)

            if showGuide {
                GestureGuide { dismissGuide() }
                    .transition(.opacity)
            }
        }
        .background { keyboardShortcuts }
        .fullScreenCover(item: $gridMode) { mode in
            PhotoGridView(pickForCompare: mode == .pickForCompare) { ids in
                compareRequest = CompareRequest(assetIDs: ids)
            }
        }
        .fullScreenCover(item: $compareRequest) { request in
            CompareView(assetIDs: request.assetIDs)
        }
        .confirmationDialog(
            "把 \(store.count(.discard)) 张丢弃的照片移到“最近删除”？",
            isPresented: $confirmCleanup,
            titleVisibility: .visible
        ) {
            Button("清空丢弃的照片", role: .destructive) {
                Task { await store.delete(store.discardedAssets) }
            }
        } message: {
            Text("照片会进入相册的“最近删除”，30 天内还可以恢复。")
        }
        .confirmationDialog("删除这张照片？", isPresented: $confirmDeleteCurrent, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let asset = store.currentAsset { Task { await store.delete([asset]) } }
            }
        }
        .onChange(of: store.lastRating) { _, event in showToast(event) }
        .task {
            if !didShowGuide { withAnimation { showGuide = true } }
        }
    }

    // MARK: - Rating

    private func commit(_ status: ImageStatus) {
        dragProgress = 0
        store.rate(status, advance: autoAdvance)
    }

    private func toggleChrome() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { chromeVisible.toggle() }
    }

    private func dismissGuide() {
        didShowGuide = true
        withAnimation { showGuide = false }
    }

    // MARK: - Top controls (glass)

    private var topControls: some View {
        VStack(spacing: 8) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    albumMenu
                    counter
                    Spacer(minLength: 0)
                    Button { gridMode = .browse } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                            .glassSurface(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("网格")
                    .accessibilityIdentifier("top.grid")
                    moreMenu
                }
            }
            filterBar
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var albumMenu: some View {
        Menu {
            ForEach(store.albums) { album in
                Button {
                    store.selectAlbum(album)
                } label: {
                    Label("\(album.title)  \(album.count)", systemImage: album.id == store.selectedAlbumID ? "checkmark" : album.symbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(store.selectedAlbum?.title ?? "全部照片").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.capsule)
            .glassSurface(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换相册")
        .accessibilityValue(store.selectedAlbum?.title ?? "全部照片")
    }

    private var counter: some View {
        Group {
            if let index = store.currentIndex {
                Text(String(format: "%02d / %d", index + 1, store.visible.count))
                    .monospacedDigit()
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .glassSurface(.capsule)
            }
        }
        .accessibilityIdentifier("top.counter")
    }

    private var moreMenu: some View {
        Menu {
            if store.visible.count > 1 {
                Button { gridMode = .pickForCompare } label: {
                    Label("选择照片对比…", systemImage: "rectangle.split.2x1")
                }
            }
            Toggle(isOn: $autoAdvance) { Label("标记后自动下一张", systemImage: "forward") }
            Button { withAnimation { showGuide = true } } label: {
                Label("操作说明", systemImage: "hand.draw")
            }
            Divider()
            Button(role: .destructive) { confirmDeleteCurrent = true } label: {
                Label("删除当前照片", systemImage: "trash")
            }
            .disabled(store.currentAsset == nil)
            Button(role: .destructive) { confirmCleanup = true } label: {
                Label("清空丢弃的照片 (\(store.count(.discard)))", systemImage: "trash.slash")
            }
            .disabled(store.count(.discard) == 0)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .glassSurface(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多")
        .accessibilityIdentifier("top.more")
    }

    /// 全部 / 保留 / 待定 / 丢弃 with counts: shows progress and filters the photos.
    private var filterBar: some View {
        HStack(spacing: 2) {
            filterItem(.all, "全部")
            filterItem(.keep, "保留")
            filterItem(.undecided, "待定")
            filterItem(.discard, "丢弃")
        }
        .padding(3)
        .glassSurface(.capsule)
    }

    private func filterItem(_ filter: PhotoFilter, _ title: String) -> some View {
        let selected = store.filter == filter
        return Button {
            store.filter = filter
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("\(store.count(filter))").monospacedDigit().opacity(0.65)
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 11)
            .frame(minHeight: 32)
            .background(selected ? GlancePalette.accent.opacity(0.28) : .clear, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(store.count(filter)) 张")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("pill.\(filter.rawValue)")
    }

    // MARK: - Overlays on the photo

    /// Always-visible mark of the current photo's rating.
    private var ratingBadge: some View {
        VStack {
            Spacer().frame(height: 118)
            HStack {
                if currentStatus != .undecided {
                    Label(currentStatus.title, systemImage: currentStatus == .keep ? "flag.fill" : "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(currentStatus == .keep ? Color.green : Color.red, in: .capsule)
                        .accessibilityIdentifier("badge.\(currentStatus.rawValue)")
                }
                Spacer()
            }
            .padding(.leading, 16)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// Big icon that grows while a photo is being dragged: release to rate.
    private var dragHUD: some View {
        let strength = abs(dragProgress)
        let keeps = dragProgress > 0
        return VStack(spacing: 8) {
            Image(systemName: keeps ? "flag.fill" : "xmark")
                .font(.system(size: 44, weight: .semibold))
            Text(strength >= 0.65 ? (keeps ? "松手保留" : "松手丢弃") : (keeps ? "保留" : "丢弃"))
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28).padding(.vertical, 22)
        .background((keeps ? Color.green : Color.red).opacity(0.9), in: .rect(cornerRadius: 20))
        .scaleEffect(0.7 + 0.5 * strength)
        .opacity(Double(min(1, strength * 1.6)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 14) {
                Text(toast.new == .undecided ? "已取消标记" : "已标为\(toast.new.title)")
                    .font(.system(size: 14, weight: .medium))
                Button("撤销") {
                    store.undoLastRating()
                    self.toast = nil
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GlancePalette.accent)
                .accessibilityIdentifier("toast.undo")
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .glassSurface(.capsule)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ event: LibraryStore.RatingEvent?) {
        guard let event else { toast = nil; return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { toast = event }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if toast?.id == event.id { withAnimation { toast = nil } }
        }
    }

    // MARK: - Rating dock (always visible; swiping the photo does the same)

    private var ratingDock: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 6) {
                dockButton(.discard, "丢弃", "xmark", tint: .red)
                dockButton(.undecided, "待定", "questionmark", tint: .gray)
                dockButton(.keep, "保留", "flag.fill", tint: .green)
                Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 28).padding(.horizontal, 2)
                Button { gridMode = .pickForCompare } label: {
                    dockLabel("对比", "rectangle.split.2x1", selected: false, tint: GlancePalette.accent)
                }
                .buttonStyle(.plain)
                .disabled(store.visible.count < 2)
                .opacity(store.visible.count < 2 ? 0.4 : 1)
                .accessibilityLabel("选择照片对比")
                .accessibilityIdentifier("dock.compare")
            }
            .padding(6)
            .glassSurface(.capsule)
        }
        .padding(.horizontal, 16)
    }

    private func dockButton(_ status: ImageStatus, _ title: String, _ symbol: String, tint: Color) -> some View {
        let selected = currentStatus == status && status != .undecided
        return Button {
            commit(status)
        } label: {
            dockLabel(title, symbol, selected: selected, tint: tint)
        }
        .buttonStyle(.plain)
        .disabled(store.currentID == nil)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("dock.\(status.rawValue)")
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func dockLabel(_ title: String, _ symbol: String, selected: Bool, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(height: 22)
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .frame(width: 62, height: 52)
        .background(selected ? tint : .clear, in: .capsule)
        .contentShape(.capsule)
    }

    // MARK: - Hardware keyboard (iPad)

    private var keyboardShortcuts: some View {
        HStack {
            Button("", action: store.previous).keyboardShortcut(.leftArrow, modifiers: [])
            Button("", action: store.next).keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { commit(.discard) }.keyboardShortcut("1", modifiers: [])
            Button("") { commit(.undecided) }.keyboardShortcut("2", modifiers: [])
            Button("") { commit(.keep) }.keyboardShortcut("3", modifiers: [])
            Button("") { commit(.discard) }.keyboardShortcut("x", modifiers: [])
            Button("") { commit(.undecided) }.keyboardShortcut("u", modifiers: [])
            Button("") { commit(.keep) }.keyboardShortcut("p", modifiers: [])
            Button("") { gridMode = .browse }.keyboardShortcut("g", modifiers: [])
            Button("") { gridMode = .pickForCompare }.keyboardShortcut("c", modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

struct EmptyFilterView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        ContentUnavailableView {
            Label(store.totalCount == 0 ? "相册里没有照片" : "这个筛选下没有照片", systemImage: "photo.on.rectangle")
        } actions: {
            if store.filter != .all {
                Button("查看全部") { store.filter = .all }
            }
        }
    }
}
