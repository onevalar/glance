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
                MainView()
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

/// iPad (regular width): filmstrip column on the left, photo on the right.
/// iPhone (compact width): the photo fills the screen, filmstrip sits above the rating buttons.
struct MainView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showColumn = true

    var body: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                if showColumn {
                    SidebarColumn()
                        .frame(width: 144)
                        .transition(.move(edge: .leading))
                    Divider()
                }
                ViewerScreen(showColumn: $showColumn)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showColumn)
        } else {
            ViewerScreen(showColumn: $showColumn)
        }
    }
}

struct SidebarColumn: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ThumbnailStrip(axis: .vertical)
            .background(GlancePalette.panel(scheme))
    }
}

struct ViewerScreen: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showColumn: Bool

    @State private var chromeVisible = true
    @State private var showAlbums = false
    @State private var confirmCleanup = false
    @State private var confirmDeleteCurrent = false
    @AppStorage("autoAdvance") private var autoAdvance = true

    var body: some View {
        ZStack {
            GlancePalette.canvas(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar
                    .opacity(chromeVisible || store.visible.isEmpty ? 1 : 0)
                    .allowsHitTesting(chromeVisible || store.visible.isEmpty)
                if store.visible.isEmpty {
                    EmptyFilterView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    caption
                    pager
                    Text("左右切换图片 · 双指缩放")
                        .font(.system(size: 12))
                        .foregroundStyle(GlancePalette.muted(scheme))
                        .padding(.vertical, 12)
                        .opacity(chromeVisible ? 1 : 0)
                    if sizeClass == .compact { Spacer(minLength: 0) }
                }
                RatingBar()
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    .padding(.top, store.visible.isEmpty ? 12 : 4)
                    .padding(.bottom, 12)
                    .opacity(chromeVisible || store.visible.isEmpty ? 1 : 0)
                    .allowsHitTesting(chromeVisible || store.visible.isEmpty)
            }
        }
        .background { arrowKeys }
        .sheet(isPresented: $showAlbums) { AlbumSheet() }
        .confirmationDialog(
            "把 \(store.discardedAssets.count) 张丢弃的照片移到“最近删除”？",
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
    }

    /// On iPhone the photo sits in a fixed 390×460 zone under the caption (Paper), not centred in all free space.
    @ViewBuilder
    private var pager: some View {
        let pager = ViewerPager(onSingleTap: {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { chromeVisible.toggle() }
        })
        if sizeClass == .compact {
            pager.frame(maxWidth: .infinity).aspectRatio(390.0 / 460.0, contentMode: .fit)
        } else {
            pager
        }
    }

    // MARK: - Navigation bar (Paper: ‹ 相册 · 过目 · 筛选)

    private var navigationBar: some View {
        ZStack {
            Text("过目")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(GlancePalette.foreground(scheme))

            HStack(spacing: 4) {
                if sizeClass == .regular {
                    Button { showColumn.toggle() } label: {
                        Image(systemName: "sidebar.leading").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("显示或隐藏缩略图")
                }
                Button { showAlbums = true } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        Text("相册").font(.system(size: 17))
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择相册")
                .accessibilityValue(store.selectedAlbum?.title ?? "全部照片")

                Spacer(minLength: 8)
                filterMenu
            }
            .foregroundStyle(GlancePalette.foreground(scheme))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var filterMenu: some View {
        Menu {
            Picker("筛选", selection: $store.filter) {
                ForEach(PhotoFilter.allCases) { filter in
                    Label(filter.rawValue, systemImage: filter.iconName).tag(filter)
                }
            }
            Divider()
            Toggle("标记后自动下一张", isOn: $autoAdvance)
            Button(role: .destructive) {
                confirmDeleteCurrent = true
            } label: {
                Label("删除当前照片", systemImage: "trash")
            }
            .disabled(store.currentAsset == nil)
            Button(role: .destructive) {
                confirmCleanup = true
            } label: {
                Label("清空丢弃的照片 (\(store.discardedAssets.count))", systemImage: "trash.slash")
            }
            .disabled(store.discardedAssets.isEmpty)
        } label: {
            Text("筛选")
                .font(.system(size: 17))
                .foregroundStyle(store.filter == .all ? GlancePalette.foreground(scheme) : GlancePalette.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("筛选和更多操作")
        .accessibilityValue(store.filter.rawValue)
    }

    /// "01 / 24 · IMG_0421" under the navigation bar.
    private var caption: some View {
        Group {
            if let index = store.currentIndex, let asset = store.currentAsset {
                let digits = max(2, String(store.visible.count).count)
                let position = String(format: "%0\(digits)d / %d", index + 1, store.visible.count)
                let name = store.displayName(of: asset)
                Text(name.isEmpty ? position : "\(position)  ·  \(name)")
            } else {
                Text(" ")
            }
        }
        .font(.system(size: 13))
        .monospacedDigit()
        .foregroundStyle(GlancePalette.muted(scheme))
        .lineLimit(1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .opacity(chromeVisible ? 1 : 0)
    }

    /// Arrow keys on an iPad keyboard.
    private var arrowKeys: some View {
        HStack {
            Button("", action: store.previous).keyboardShortcut(.leftArrow, modifiers: [])
            Button("", action: store.next).keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// "相册" sheet: choose which part of the library to cull.
struct AlbumSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.albums) { album in
                Button {
                    store.selectAlbum(album)
                    dismiss()
                } label: {
                    HStack {
                        Label(album.title, systemImage: album.symbol)
                        Spacer()
                        Text("\(album.count)").foregroundStyle(.secondary).monospacedDigit()
                        if album.id == store.selectedAlbumID {
                            Image(systemName: "checkmark").foregroundStyle(GlancePalette.accent)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .foregroundStyle(.primary)
                .accessibilityAddTraits(album.id == store.selectedAlbumID ? .isSelected : [])
            }
            .navigationTitle("相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
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
