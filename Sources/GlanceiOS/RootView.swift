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
            .animation(.easeInOut(duration: 0.25), value: showColumn)
        } else {
            ViewerScreen(showColumn: $showColumn)
        }
    }
}

struct SidebarColumn: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        ThumbnailStrip(axis: .vertical)
            .background(Color(.secondarySystemBackground))
    }
}

struct ViewerScreen: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var showColumn: Bool

    @State private var chromeVisible = true
    @State private var confirmCleanup = false
    @State private var confirmDeleteCurrent = false
    @AppStorage("autoAdvance") private var autoAdvance = true

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground).ignoresSafeArea()

            if store.visible.isEmpty {
                EmptyFilterView()
            } else {
                ViewerPager(onSingleTap: { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } })
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            .opacity(chromeVisible || store.visible.isEmpty ? 1 : 0)
            .allowsHitTesting(chromeVisible || store.visible.isEmpty)
        }
        .background { arrowKeys }
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

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            if sizeClass == .regular {
                Button {
                    showColumn.toggle()
                } label: {
                    Image(systemName: "sidebar.leading")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: .circle)
            }

            filterMenu

            Spacer(minLength: 0)

            positionLabel

            Spacer(minLength: 0)

            moreMenu
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var filterMenu: some View {
        Menu {
            Picker("筛选", selection: $store.filter) {
                ForEach(PhotoFilter.allCases) { filter in
                    Label(filter.rawValue, systemImage: filter.iconName).tag(filter)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.filter.iconName)
                Text(store.filter.rawValue)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: .capsule)
        }
        .tint(.primary)
    }

    private var positionLabel: some View {
        VStack(spacing: 1) {
            if let index = store.currentIndex {
                Text("\(index + 1) / \(store.visible.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let asset = store.currentAsset {
                    Text(Self.caption(for: asset))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Toggle("标记后自动下一张", isOn: $autoAdvance)
            Divider()
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
            Image(systemName: "ellipsis")
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: .circle)
        }
        .tint(.primary)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if sizeClass != .regular, !store.visible.isEmpty {
                ThumbnailStrip(axis: .horizontal)
                    .frame(height: 72)
            }
            RatingBar()
                .padding(.horizontal, 14)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
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

    private static func caption(for asset: PHAsset) -> String {
        let date = asset.creationDate?.formatted(.dateTime.year().month().day().hour().minute()) ?? ""
        return "\(date) · \(asset.pixelWidth)×\(asset.pixelHeight)"
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
