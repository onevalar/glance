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

/// The only screen. Three clearly separate layers, nothing is offered twice:
///
/// 1. **Top bar** (glass on the plain canvas): 照片 (grid), the scope pill (position + album + rating filter), 更多.
/// 2. **Photo area**: a fixed region between the bars. Swipe sideways = previous / next, pull **up** = stars,
///    pull **down** = trash. A tap hides both bars and the photo fills the screen.
/// 3. **Dock** (glass on the canvas): 🗑 · stars · 对比 — the same actions as the gestures, always visible.
struct ViewerScreen: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Sheet: String, Identifiable {
        case photos, comparePicker, settings
        var id: String { rawValue }
    }

    struct CompareRequest: Identifiable {
        let id = UUID()
        let assetIDs: [String]
    }

    @StateObject private var drag = RatingDragModel()
    @State private var chromeVisible = true
    @State private var toast: LibraryStore.RatingEvent?
    @State private var sheet: Sheet?
    @State private var compareRequest: CompareRequest?
    @State private var confirmCleanup = false
    @AppStorage("autoAdvance") private var autoAdvance = true
    @AppStorage("starScale") private var starScale = 5
    @AppStorage("didShowGestureGuide") private var didShowGuide = false
    @State private var showGuide = false

    private var currentMeta: ImageMetadata {
        store.currentID.map { metadata.getMetadata(forKey: $0) } ?? ImageMetadata()
    }

    var body: some View {
        ZStack {
            GlancePalette.canvas(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                if chromeVisible {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                photoArea
                if chromeVisible {
                    VStack(spacing: 10) {
                        toastView
                        ratingDock
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            StarRiseHUD(model: drag, count: starScale, current: currentMeta.rating)
            TrashRiseHUD(model: drag)

            if !chromeVisible { toastView.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 40) }

            if showGuide {
                GestureGuide(starScale: starScale) { dismissGuide() }
                    .transition(.opacity)
            }
        }
        .background { keyboardShortcuts }
        .fullScreenCover(item: $sheet) { sheet in
            switch sheet {
            case .photos:
                PhotoGridView()
            case .comparePicker:
                ComparePickerView { ids in compareRequest = CompareRequest(assetIDs: ids) }
            case .settings:
                SettingsSheet(onShowGuide: { withAnimation { showGuide = true } })
            }
        }
        .fullScreenCover(item: $compareRequest) { request in
            CompareView(assetIDs: request.assetIDs)
        }
        .confirmationDialog(
            "把 \(store.count(.discarded)) 张已丢弃的照片移到“最近删除”？",
            isPresented: $confirmCleanup,
            titleVisibility: .visible
        ) {
            Button("删除这 \(store.count(.discarded)) 张照片", role: .destructive) {
                Task { await store.delete(store.discardedAssets) }
            }
        } message: {
            Text("照片会进入相册的“最近删除”，30 天内还可以恢复。系统还会再确认一次。")
        }
        .onChange(of: store.lastRating) { _, event in showToast(event) }
        .onChange(of: starScale) { _, scale in
            if case .stars(let n) = store.filter, n > scale { store.filter = .all }
        }
        .task {
            if !didShowGuide { withAnimation { showGuide = true } }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: chromeVisible)
    }

    // MARK: - Photo area

    private var photoArea: some View {
        Group {
            if store.visible.isEmpty {
                EmptyFilterView()
            } else {
                PhotoPager(
                    assets: store.visible,
                    currentID: store.currentID,
                    drag: drag,
                    onPageChange: { id in
                        // A settled page: the only moment the store hears about swiping.
                        if store.currentID != id { store.currentID = id }
                    },
                    onSingleTap: { toggleChrome() },
                    onCommit: { direction, x, y in commit(direction, x, y) },
                    isDiscarded: { id in metadata.getMetadata(forKey: id).isDiscarded }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea(edges: chromeVisible ? [] : .all)
    }

    // MARK: - Rating gestures

    private func commit(_ direction: Int, _ x: CGFloat, _ y: CGFloat) {
        if direction < 0 {
            // The photo has just dropped into the trash: mark it.
            store.discard(advance: autoAdvance)
            return
        }
        // Pulled up: only a star the finger is actually on counts; anywhere else cancels.
        guard let slot = RatingDragModel.slot(x: x, y: y, count: starScale, screenWidth: drag.screenWidth) else { return }
        store.setRating(slot, advance: autoAdvance && slot > 0)
    }

    private func toggleChrome() {
        chromeVisible.toggle()
    }

    private func dismissGuide() {
        didShowGuide = true
        withAnimation { showGuide = false }
    }

    // MARK: - Top bar

    private var topBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button { sheet = .photos } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                        .glassSurface(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("全部照片")
                .accessibilityIdentifier("top.photos")

                Spacer(minLength: 0)
                scopeMenu
                Spacer(minLength: 0)
                moreMenu
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// Position, album and rating filter in one control (they all answer "which photos am I looking at").
    private var scopeMenu: some View {
        Menu {
            Section("相册") {
                ForEach(store.albums) { album in
                    Button {
                        store.selectAlbum(album)
                    } label: {
                        Label("\(album.title)  \(album.count)",
                              systemImage: album.id == store.selectedAlbumID ? "checkmark" : album.symbol)
                    }
                    .accessibilityIdentifier("scope.album.\(album.id)")
                }
            }
            Section("评分") {
                ForEach(PhotoFilter.options(scale: starScale)) { option in
                    Button {
                        store.filter = option
                    } label: {
                        Label("\(option.title)  \(store.count(option))",
                              systemImage: option == store.filter ? "checkmark" : option.symbol)
                    }
                    .accessibilityIdentifier("filter.\(option.id)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                if store.selectedAlbumID != AlbumChoice.allPhotosID {
                    Text(store.selectedAlbum?.title ?? "").lineLimit(1).frame(maxWidth: 90)
                    Text("·").opacity(0.5)
                }
                if store.filter != .all {
                    Image(systemName: store.filter.symbol).font(.system(size: 12))
                    Text(store.filter.title)
                    Text("·").opacity(0.5)
                }
                Text(positionText).monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).opacity(0.7)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(.capsule)
            .glassSurface(.capsule, tint: store.filter == .all ? nil : GlancePalette.accent.opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("相册和评分筛选")
        .accessibilityValue(positionText)
        .accessibilityIdentifier("top.scope")
    }

    private var positionText: String {
        guard let index = store.currentIndex else { return "0 / \(store.visible.count)" }
        return String(format: "%02d / %d", index + 1, store.visible.count)
    }

    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $autoAdvance) { Label("评分后自动下一张", systemImage: "forward") }
            Button { sheet = .settings } label: { Label("设置", systemImage: "gearshape") }
                .accessibilityIdentifier("menu.settings")
            Button { withAnimation { showGuide = true } } label: {
                Label("操作说明", systemImage: "hand.draw")
            }
            Divider()
            Button(role: .destructive) { confirmCleanup = true } label: {
                Label("清空已丢弃的照片 (\(store.count(.discarded)))…", systemImage: "trash.slash")
            }
            .disabled(store.count(.discarded) == 0)
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

    // MARK: - Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 14) {
                Text(toast.message).font(.system(size: 14, weight: .medium))
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

    // MARK: - Dock: the same actions as the gestures, always visible

    private var ratingDock: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 2) {
                Button { store.discard(advance: autoAdvance) } label: {
                    Image(systemName: currentMeta.isDiscarded ? "trash.fill" : "trash")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(currentMeta.isDiscarded ? Color.white : Color.primary)
                        .frame(width: 46, height: 46)
                        .background(currentMeta.isDiscarded ? Color.red : .clear, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(store.currentID == nil)
                .accessibilityLabel("丢弃")
                .accessibilityAddTraits(currentMeta.isDiscarded ? .isSelected : [])
                .accessibilityIdentifier("dock.discard")

                divider

                ForEach(1...starScale, id: \.self) { index in
                    Button { store.rate(stars: index, advance: autoAdvance) } label: {
                        Image(systemName: index <= currentMeta.rating ? "star.fill" : "star")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(index <= currentMeta.rating ? Color.yellow : Color.primary)
                            .frame(width: starScale == 5 ? 38 : 46, height: 46)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.currentID == nil)
                    .accessibilityLabel("\(index) 星")
                    .accessibilityAddTraits(index == currentMeta.rating ? .isSelected : [])
                    .accessibilityIdentifier("dock.star.\(index)")
                }

                divider

                Button { sheet = .comparePicker } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(store.visible.count < 2)
                .opacity(store.visible.count < 2 ? 0.4 : 1)
                .accessibilityLabel("选择照片对比")
                .accessibilityIdentifier("dock.compare")
            }
            .foregroundStyle(.primary)
            .padding(5)
            .glassSurface(.capsule)
        }
        .padding(.horizontal, 12)
    }

    private var divider: some View {
        Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 26).padding(.horizontal, 4)
    }

    // MARK: - Hardware keyboard (iPad)

    private var keyboardShortcuts: some View {
        HStack {
            Button("", action: store.previous).keyboardShortcut(.leftArrow, modifiers: [])
            Button("", action: store.next).keyboardShortcut(.rightArrow, modifiers: [])
            ForEach(1...5, id: \.self) { n in
                Button("") { if n <= starScale { store.rate(stars: n, advance: autoAdvance) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [])
            }
            Button("") { store.discard(advance: autoAdvance) }.keyboardShortcut("x", modifiers: [])
            Button("") { store.discard(advance: autoAdvance) }.keyboardShortcut(.delete, modifiers: [])
            Button("") { sheet = .photos }.keyboardShortcut("g", modifiers: [])
            Button("") { sheet = .comparePicker }.keyboardShortcut("c", modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Settings: star scale, auto-advance, gesture guide.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("starScale") private var starScale = 5
    @AppStorage("autoAdvance") private var autoAdvance = true
    var onShowGuide: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("评分星级", selection: $starScale) {
                        Text("3 星").tag(3)
                        Text("5 星").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.starScale")
                } header: {
                    Text("评分")
                } footer: {
                    Text("上滑评分时，屏幕上会出现 3 颗或 5 颗星，手指停在哪颗就是几星。已经打过的星级不会丢。")
                }
                Section {
                    Toggle("评分或丢弃后自动看下一张", isOn: $autoAdvance)
                }
                Section {
                    Button("查看操作说明") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onShowGuide() }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium])
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
