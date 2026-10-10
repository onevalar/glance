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
/// 1. **Top bar** (glass on the plain canvas), one job per control: the album menu (what am I looking at, plus the
///    thumbnail overview), the position pill (where am I + rating filter), and 更多 (star scale, auto-advance, guide).
/// 2. **Photo** (full screen, under the bars): at rest it fits between the bars; zooming in hides the bars and
///    lets it use the whole screen. Swipe sideways = previous / next, pull **up** = throw it into a star, pull
///    **down** = drop it in the trash bin. A tap hides both bars.
/// 3. **Dock** (glass on the canvas): 🗑 · stars · 对比 — the same actions as the gestures, always visible.
///    In the discard pile it becomes 恢复 · 清空.
struct ViewerScreen: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Sheet: String, Identifiable {
        case photos, comparePicker
        var id: String { rawValue }
    }

    struct CompareRequest: Identifiable {
        let id = UUID()
        let assetIDs: [String]
    }

    @State private var phase = DragPhaseModel()   // not observed here: only `ChromeFade` follows it
    @State private var screenFrame: CGRect = .zero
    @State private var topBarFrame: CGRect = .zero
    @State private var dockFrame: CGRect = .zero
    @State private var safeFrame: CGRect = .zero
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
            GlancePalette.canvas(scheme)
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { screenFrame = $0 }

            photoArea

            VStack(spacing: 0) {
                if chromeVisible {
                    ChromeFade(phase: phase) {
                        topBar.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { topBarFrame = $0 }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if chromeVisible {
                    ChromeFade(phase: phase) {
                        VStack(spacing: 10) {
                            toastView
                            ratingDock.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { dockFrame = $0 }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { safeFrame = $0 }

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
                    phase: phase,
                    starCount: starScale,
                    starRowY: topBarFrame.height > 0 ? topBarFrame.midY : 0,
                    fitInsets: fitInsets,
                    onPageChange: { id in
                        // A settled page: the only moment the store hears about swiping.
                        if store.currentID != id { store.currentID = id }
                    },
                    onSingleTap: { toggleChrome() },
                    onZoomChange: { zoomed in
                        // Like Photos: zooming in clears the screen for the picture.
                        if zoomed, chromeVisible { chromeVisible = false }
                    },
                    onCommit: { outcome in commit(outcome) }
                )
                .ignoresSafeArea()
            }
        }
    }

    /// Room kept free around a resting photo, in screen coordinates: between the two bars (with a little air),
    /// or inside the safe area when the bars are hidden. Zooming in may still use the whole screen.
    private var fitInsets: UIEdgeInsets {
        guard screenFrame.height > 0 else { return .zero }
        if chromeVisible, topBarFrame.height > 0, dockFrame.height > 0 {
            return UIEdgeInsets(top: max(0, topBarFrame.maxY - screenFrame.minY + 14), left: 0,
                                bottom: max(0, screenFrame.maxY - dockFrame.minY + 14), right: 0)
        }
        guard safeFrame.height > 0 else { return .zero }
        return UIEdgeInsets(top: max(0, safeFrame.minY - screenFrame.minY), left: 0,
                            bottom: max(0, screenFrame.maxY - safeFrame.maxY), right: 0)
    }

    // MARK: - Rating gestures

    private func commit(_ outcome: PullOutcome) {
        switch outcome {
        case .discard:
            // The photo has just dropped into the bin: it stays in the pile (dropping it again changes nothing).
            if !currentMeta.isDiscarded {
                store.discard(advance: autoAdvance)
            } else if autoAdvance {
                store.next()
            }
        case .rate(let stars):
            store.setRating(stars, advance: autoAdvance)
        }
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
                albumMenu
                Spacer(minLength: 0)
                positionMenu
                Spacer(minLength: 0)
                moreMenu
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var inDiscardPile: Bool { store.filter == .discarded }

    /// Which photos: the album (or the whole library), and the thumbnail overview of them.
    private var albumMenu: some View {
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
            Section {
                Button { sheet = .photos } label: { Label("缩略图浏览", systemImage: "square.grid.3x3") }
                    .accessibilityIdentifier("scope.grid")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 15, weight: .medium))
                Text(store.selectedAlbum?.title ?? "全部照片").lineLimit(1).frame(maxWidth: 84)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).opacity(0.7)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.capsule)
            .glassSurface(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("相册")
        .accessibilityValue(store.selectedAlbum?.title ?? "全部照片")
        .accessibilityIdentifier("top.album")
    }

    /// Where am I, and which ratings are shown. The discard pile is marked in light red.
    private var positionMenu: some View {
        Menu {
            Section("按评分筛选") {
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
                if store.filter != .all {
                    Image(systemName: store.filter.symbol).font(.system(size: 12, weight: .semibold))
                    Text(store.filter.title)
                    Text("·").opacity(0.5)
                }
                Text(positionText).monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).opacity(0.7)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(inDiscardPile ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(.capsule)
            .glassSurface(.capsule, tint: pillTint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("评分筛选")
        .accessibilityValue(positionText)
        .accessibilityIdentifier("top.scope")
    }

    private var pillTint: Color? {
        switch store.filter {
        case .all: return nil
        case .discarded: return Color.red.opacity(0.22)
        default: return GlancePalette.accent.opacity(0.35)
        }
    }

    private var positionText: String {
        guard let index = store.currentIndex else { return "0 / \(store.visible.count)" }
        return String(format: "%02d / %d", index + 1, store.visible.count)
    }

    /// Preferences, in one small menu: star scale, moving on after a decision, the guide.
    private var moreMenu: some View {
        Menu {
            Picker(selection: $starScale) {
                Text("5 星").tag(5)
                Text("3 星").tag(3)
            } label: {
                Label("评分方式", systemImage: "star")
                Text("\(starScale) 星")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("menu.starScale")
            Toggle(isOn: $autoAdvance) { Label("评分或丢弃后自动下一张", systemImage: "forward") }
                .accessibilityIdentifier("menu.autoAdvance")
            Divider()
            Button { withAnimation { showGuide = true } } label: {
                Label("操作说明", systemImage: "hand.draw")
            }
            .accessibilityIdentifier("menu.guide")
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

    @ViewBuilder
    private var ratingDock: some View {
        GlassGroup(spacing: 10) {
            Group {
                if inDiscardPile { discardPileDock } else { normalDock }
            }
            .foregroundStyle(.primary)
            .padding(5)
            .glassSurface(.capsule)
        }
        .padding(.horizontal, 12)
    }

    /// 🗑 · stars · 对比. A discarded photo (met while browsing) shows 恢复 and a quiet "已丢弃" instead.
    private var normalDock: some View {
        let discarded = currentMeta.isDiscarded
        let rating = currentMeta.rating
        return HStack(spacing: 2) {
            Button { store.discard(advance: autoAdvance && !discarded) } label: {
                Image(systemName: discarded ? "arrow.uturn.backward" : "trash")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(store.currentID == nil)
            .accessibilityLabel(discarded ? "恢复这张照片" : "丢弃")
            .accessibilityAddTraits(discarded ? .isSelected : [])
            .accessibilityIdentifier("dock.discard")

            divider

            if discarded {
                // A discarded photo has no rating: the stars give way to its status.
                Label("已丢弃", systemImage: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .frame(width: CGFloat(starScale) * (starScale == 5 ? 38 : 46), height: 38)
                    .background(Color.red.opacity(0.10), in: .capsule)
                    .accessibilityIdentifier("dock.status.discarded")
            } else {
                ForEach(1...starScale, id: \.self) { index in
                    let filled = index <= rating
                    Button { store.rate(stars: index, advance: autoAdvance) } label: {
                        Image(systemName: filled ? "star.fill" : "star")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(filled ? AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 1, green: 0.86, blue: 0.3), Color(red: 1, green: 0.62, blue: 0.1)],
                                startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.primary.opacity(0.8)))
                            .scaleEffect(index == rating ? 1.14 : 1)
                            .frame(width: starScale == 5 ? 38 : 46, height: 46)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.currentID == nil)
                    .accessibilityLabel("\(index) 星")
                    .accessibilityAddTraits(index == rating ? .isSelected : [])
                    .accessibilityIdentifier("dock.star.\(index)")
                }
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
        .animation(.spring(duration: 0.25, bounce: 0.3), value: rating)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: discarded)
    }

    /// In the discard pile the only decisions left: take this one back, or empty the pile.
    private var discardPileDock: some View {
        let count = store.count(.discarded)
        return HStack(spacing: 2) {
            Button { store.discard(advance: false) } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(store.currentID == nil)
            .accessibilityLabel("恢复这张照片")
            .accessibilityIdentifier("dock.restore")

            divider

            Button { confirmCleanup = true } label: {
                Label("清空 \(count) 张", systemImage: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .accessibilityLabel("清空已丢弃的 \(count) 张照片")
            .accessibilityIdentifier("dock.empty")
        }
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
            Button("") { store.discard(advance: autoAdvance && !currentMeta.isDiscarded) }.keyboardShortcut("x", modifiers: [])
            Button("") { store.discard(advance: autoAdvance && !currentMeta.isDiscarded) }.keyboardShortcut(.delete, modifiers: [])
            Button("") { sheet = .photos }.keyboardShortcut("g", modifiers: [])
            Button("") { sheet = .comparePicker }.keyboardShortcut("c", modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Fades the bars away while a photo is being pulled up or down, so nothing competes with the gesture.
struct ChromeFade<Content: View>: View {
    @ObservedObject var phase: DragPhaseModel
    @ViewBuilder var content: Content

    var body: some View {
        let idle = phase.phase == .idle
        content
            .opacity(idle ? 1 : 0)
            .allowsHitTesting(idle)
            .animation(.easeOut(duration: 0.16), value: idle)
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
