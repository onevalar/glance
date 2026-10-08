//
//  ImageCompareView.swift
//  Glance
//

import SwiftUI

/// Keeps decoded pictures around while comparing; pan and zoom redraw the grid many times a second
/// and must not decode every file again each time.
@MainActor
final class CompareImageStore: ObservableObject {
    @Published private(set) var revision = 0
    private var images: [URL: NSImage] = [:]

    func image(for url: URL) -> NSImage? {
        if let cached = images[url] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images[url] = image
        return image
    }

    /// Drops pictures that left the selection.
    func keep(_ urls: [URL]) {
        let wanted = Set(urls)
        images = images.filter { wanted.contains($0.key) }
    }

    /// Files changed on disk (rotated, cropped): decode again.
    func invalidate() {
        images.removeAll()
        revision += 1
    }
}

struct ImageCompareView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var store = CompareImageStore()
    @ObservedObject var session: CompareSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var metadataRevision = 0
    var onScaleChanged: ((CGFloat) -> Void)?

    private var selectedUrls: [URL] {
        appState.selectedImageIndices.sorted().compactMap { index in
            appState.imageFiles.indices.contains(index) ? appState.imageFiles[index] : nil
        }
    }

    private var columnCount: Int {
        let count = selectedUrls.count
        return count == 4 ? 2 : min(3, max(1, count))
    }

    var body: some View {
        GeometryReader { geometry in
            let rows = max(1, Int(ceil(Double(selectedUrls.count) / Double(columnCount))))
            let cardHeight = max(140, (geometry.size.height - 144 - CGFloat(rows - 1) * 12) / CGFloat(rows))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount), spacing: 12) {
                    ForEach(selectedUrls, id: \.self) { url in
                        photoCard(url, height: cardHeight)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.horizontal, 16)
            .padding(.top, 52)
            .padding(.bottom, 76)
        }
        .background(GlancePalette.canvas(colorScheme))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("并排比较 · \(selectedUrls.count) 张照片")
                    .font(.system(size: 13, weight: .medium))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: Binding(get: { session.isSynchronized }, set: { session.setSynchronized($0) })) {
                    Label("同步缩放", systemImage: session.isSynchronized ? "link" : "link.badge.plus")
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
                .accessibilityValue(session.isSynchronized ? "开启" : "关闭")
                Button("退出比较") {
                    if let url = session.activeURL, let index = appState.imageFiles.firstIndex(of: url) {
                        appState.selectSingleImage(index: index)
                    }
                }
            }
        }
        .onAppear { prepareSelection(selectedUrls) }
        .onChange(of: selectedUrls) { _, urls in store.keep(urls); prepareSelection(urls) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("open-image"))) { _ in store.invalidate() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("metadata-updated"))) { _ in metadataRevision += 1 }
    }

    private func prepareSelection(_ urls: [URL]) {
        session.select(urls)
        if let current = appState.currentImageURL { session.focus(current) }
    }

    private func photoCard(_ url: URL, height: CGFloat) -> some View {
        let _ = metadataRevision
        let metadata = MetadataManager.shared.getMetadata(for: url)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { focus(url) } label: {
                    Text(url.lastPathComponent).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择照片：\(url.lastPathComponent)")
                Text("\(Int((session.transform(for: url).zoom * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12).frame(height: 36)

            if let image = store.image(for: url) {
                ZoomableImageView(
                    image: image,
                    cropRect: metadata.cropRect,
                    sharedZoom: zoomBinding(for: url),
                    sharedPan: panBinding(for: url),
                    isShared: true,
                    onScaleChanged: { scale in
                        if session.activeURL == url {
                            DispatchQueue.main.async { onScaleChanged?(scale) }
                        }
                    },
                    onClick: { focus(url) }
                )
                .frame(height: max(40, height - 80))
            } else {
                Image(systemName: "photo").font(.system(size: 32)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: max(40, height - 80))
            }

            HStack {
                Button(metadata.status == .discard ? "已丢弃" : "丢弃") { rate(url, status: .discard) }
                    .accessibilityLabel("丢弃：\(url.lastPathComponent)")
                Spacer(minLength: 4)
                Button(metadata.status == .keep ? "已保留" : "标记保留") { rate(url, status: .keep) }
                    .accessibilityLabel("保留：\(url.lastPathComponent)")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .tint(.primary)
            .padding(.horizontal, 12).frame(height: 44)
        }
        .background(GlancePalette.raised(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
            session.activeURL == url ? GlancePalette.accent : GlancePalette.border(colorScheme), lineWidth: 1))
    }

    private func focus(_ url: URL) {
        session.focus(url)
        if let index = appState.imageFiles.firstIndex(of: url) {
            appState.selectedImageIndex = index
            appState.currentImageURL = url
        }
    }

    private func zoomBinding(for url: URL) -> Binding<CGFloat> {
        Binding(get: { session.transform(for: url).zoom }, set: {
            var transform = session.transform(for: url)
            transform.zoom = $0
            session.update(transform, for: url)
        })
    }

    private func panBinding(for url: URL) -> Binding<CGPoint> {
        Binding(get: { session.transform(for: url).pan }, set: {
            var transform = session.transform(for: url)
            transform.pan = $0
            session.update(transform, for: url)
        })
    }

    private func rate(_ url: URL, status: ImageStatus) {
        focus(url)
        MetadataManager.shared.updateMetadata(for: url) { $0.status = status }
        NotificationCenter.default.post(name: Notification.Name("metadata-updated"), object: nil)
        if appState.activeFilter != .all { appState.updateFilteredImages() }
    }
}
