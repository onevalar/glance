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

/// The only screen: the photo fills the display and every control floats over it on Liquid Glass.
///
/// - left / right: previous / next photo
/// - drag **up**: stars rise from the bottom; the star under the finger is the rating (release to set)
/// - drag **down**: a trash can rises; drop the photo in to mark it discarded (nothing is deleted yet)
/// The same actions are always available from the glass dock at the bottom.
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
    @State private var dragOffset: CGFloat = 0
    @State private var dragX: CGFloat = 0.5
    @State private var fallToken = 0
    @State private var toast: LibraryStore.RatingEvent?
    @State private var gridMode: GridMode?
    @State private var compareRequest: CompareRequest?
    @State private var showSettings = false
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

            if store.visible.isEmpty {
                EmptyFilterView()
            } else {
                ViewerPager(
                    onSingleTap: { toggleChrome() },
                    onVerticalDrag: { offset, x in dragOffset = offset; dragX = x },
                    onVerticalCommit: { direction, x in commit(direction, x) },
                    discardFallToken: fallToken
                )
                .ignoresSafeArea()
            }

            ratingBadge
            starHUD
            trashHUD

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
                GestureGuide(starScale: starScale) { dismissGuide() }
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
        .sheet(isPresented: $showSettings) { SettingsSheet(onShowGuide: { withAnimation { showGuide = true } }) }
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
    }

    // MARK: - Rating

    private func starsFor(x: CGFloat) -> Int {
        min(max(Int((x * CGFloat(starScale)).rounded(.up)), 1), starScale)
    }

    private func commit(_ direction: Int, _ x: CGFloat) {
        dragOffset = 0
        if direction > 0 {
            store.rate(stars: starsFor(x: x), advance: autoAdvance)
        } else {
            // Let the photo drop into the trash first, then mark it.
            fallToken += 1
            Task {
                try? await Task.sleep(nanoseconds: 230_000_000)
                store.discard(advance: autoAdvance)
            }
        }
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
            filterMenu
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
            Button(role: .destructive) { confirmCleanup = true } label: {
                Label("清空已丢弃的照片 (\(store.count(.discarded)))…", systemImage: "trash.slash")
            }
            .disabled(store.count(.discarded) == 0)
            Divider()
            Button { showSettings = true } label: { Label("设置", systemImage: "gearshape") }
                .accessibilityIdentifier("menu.settings")
            Button { withAnimation { showGuide = true } } label: {
                Label("操作说明", systemImage: "hand.draw")
            }
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

    /// Current filter with its count; opens the list of star levels, unrated and discarded.
    private var filterMenu: some View {
        Menu {
            ForEach(PhotoFilter.options(scale: starScale)) { option in
                Button {
                    store.filter = option
                } label: {
                    Label("\(option.title)  \(store.count(option))",
                          systemImage: option == store.filter ? "checkmark" : option.symbol)
                }
                .accessibilityIdentifier("filter.\(option.id)")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.filter.symbol).font(.system(size: 13))
                Text(store.filter.title)
                Text("\(store.count(store.filter))").monospacedDigit().opacity(0.65)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .contentShape(.capsule)
            .glassSurface(.capsule, tint: store.filter == .all ? nil : GlancePalette.accent.opacity(0.55))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("按评分筛选")
        .accessibilityValue("\(store.filter.title) \(store.count(store.filter)) 张")
        .accessibilityIdentifier("filter.menu")
    }

    // MARK: - Overlays on the photo

    /// Always-visible mark of the current photo's rating.
    private var ratingBadge: some View {
        VStack {
            Spacer().frame(height: 126)
            HStack {
                if currentMeta.isDiscarded {
                    Label("已丢弃", systemImage: "trash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.red, in: .capsule)
                        .accessibilityIdentifier("badge.discarded")
                } else if currentMeta.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<currentMeta.rating, id: \.self) { _ in
                            Image(systemName: "star.fill").font(.system(size: 12))
                        }
                    }
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.yellow, in: .capsule)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(currentMeta.rating) 星")
                    .accessibilityIdentifier("badge.stars.\(currentMeta.rating)")
                }
                Spacer()
            }
            .padding(.leading, 16)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// Stars that rise while a photo is pulled up; the one under the finger sets the rating.
    private var starHUD: some View {
        let progress = min(max(dragOffset / 70, 0), 1)
        let selected = starsFor(x: dragX)
        return VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(1...starScale, id: \.self) { index in
                    Image(systemName: index <= selected ? "star.fill" : "star")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(index <= selected ? Color.yellow : Color.white.opacity(0.85))
                        .scaleEffect(index == selected ? 1.3 : 1)
                        .frame(maxWidth: .infinity)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .animation(.spring(duration: 0.18), value: selected)
                }
            }
            .padding(.horizontal, 8)
            Text("松手评 \(selected) 星")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.black.opacity(0.55), in: .capsule)
        }
        .offset(y: (1 - progress) * 60 - 90)
        .opacity(Double(progress))
        .sensoryFeedback(.selection, trigger: selected)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A trash can that rises as the photo is pulled down; past the threshold it opens ("松手丢弃").
    private var trashHUD: some View {
        let progress = min(max(-dragOffset / 70, 0), 1)
        let ready = progress >= 1
        return VStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: ready ? "trash.fill" : "trash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(ready ? Color.red : Color.black.opacity(0.55), in: .circle)
                    .scaleEffect(0.7 + 0.3 * progress + (ready ? 0.18 : 0))
                    .animation(.spring(duration: 0.2), value: ready)
                Text(ready ? "松手丢弃" : "继续下拉")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: .capsule)
            }
            .offset(y: (1 - progress) * 140)
            .opacity(Double(progress))
            .padding(.bottom, 110)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: ready)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

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

                Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 26).padding(.horizontal, 4)

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

                Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 26).padding(.horizontal, 4)

                Button { gridMode = .pickForCompare } label: {
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
            Button("") { gridMode = .browse }.keyboardShortcut("g", modifiers: [])
            Button("") { gridMode = .pickForCompare }.keyboardShortcut("c", modifiers: [])
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
