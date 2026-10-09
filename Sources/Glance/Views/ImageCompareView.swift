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
    @State private var imageAreaSize: CGSize = .zero
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
        VStack(spacing: 0) {
            GlanceTitleBar {
                Text("并排比较 · \(selectedUrls.count) 张照片")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GlancePalette.foreground(colorScheme))
            } trailing: {
                Toggle(isOn: Binding(get: { session.isSynchronized }, set: { session.setSynchronized($0) })) {
                    Label("同步缩放", systemImage: session.isSynchronized ? "link" : "link.badge.plus")
                }
                .toggleStyle(.button)
                .buttonStyle(CompareChipStyle(prominent: session.isSynchronized))
                .accessibilityValue(session.isSynchronized ? "开启" : "关闭")
                Button("退出比较") { exitComparison() }
                    .buttonStyle(CompareChipStyle())
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedUrls.count == 2 ? "相邻的两张，放在一起看。" : "\(selectedUrls.count) 张照片，放在一起看。")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(GlancePalette.foreground(colorScheme))
                    Spacer()
                    Text("⌘ 点击缩略图进入多选")
                        .font(.system(size: 12))
                        .foregroundStyle(GlancePalette.muted(colorScheme))
                }

                GeometryReader { geometry in
                    let rows = max(1, Int(ceil(Double(selectedUrls.count) / Double(columnCount))))
                    let cardHeight = max(160, (geometry.size.height - CGFloat(rows - 1) * 24) / CGFloat(rows))
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: columnCount), spacing: 24) {
                            ForEach(selectedUrls, id: \.self) { url in
                                photoCard(url, height: cardHeight, width: (geometry.size.width - CGFloat(columnCount - 1) * 24) / CGFloat(columnCount))
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.never)
                }

                HStack {
                    Text("各图以自己的适应窗口比例同步缩放，比较不同尺寸仍保持对齐。")
                        .font(.system(size: 12))
                        .foregroundStyle(GlancePalette.muted(colorScheme))
                    Spacer()
                    Button("1:1 原图") { showActualSize() }
                        .buttonStyle(CompareChipStyle())
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(GlancePalette.canvas(colorScheme))
        .onAppear { prepareSelection(selectedUrls) }
        .onChange(of: selectedUrls) { _, urls in store.keep(urls); prepareSelection(urls) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("open-image"))) { _ in store.invalidate() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("metadata-updated"))) { _ in metadataRevision += 1 }
    }

    private func prepareSelection(_ urls: [URL]) {
        session.select(urls)
        if let current = appState.currentImageURL { session.focus(current) }
    }

    private func photoCard(_ url: URL, height: CGFloat, width: CGFloat) -> some View {
        let _ = metadataRevision
        let metadata = MetadataManager.shared.getMetadata(for: url)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { focus(url) } label: {
                    Text(url.lastPathComponent).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择照片：\(url.lastPathComponent)")
                Text(zoomLabel(for: url))
                    .monospacedDigit().foregroundStyle(GlancePalette.muted(colorScheme))
            }
            .font(.system(size: 12))
            .foregroundStyle(GlancePalette.secondary(colorScheme))
            .padding(.horizontal, 16).frame(height: 40)

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
                .frame(height: max(40, height - 96))
                .padding(.horizontal, 16)
                .onAppear { imageAreaSize = CGSize(width: width - 32, height: max(40, height - 96)) }
            } else {
                Image(systemName: "photo").font(.system(size: 32)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: max(40, height - 96))
            }

            HStack {
                Button(metadata.status == .discard ? "已丢弃" : "丢弃") { rate(url, status: .discard) }
                    .buttonStyle(CompareChipStyle(prominent: metadata.status == .discard, compact: true))
                    .accessibilityLabel("丢弃：\(url.lastPathComponent)")
                Spacer(minLength: 4)
                Button(metadata.status == .keep ? "已保留" : "标记保留") { rate(url, status: .keep) }
                    .buttonStyle(CompareChipStyle(prominent: metadata.status == .keep, compact: true))
                    .accessibilityLabel("保留：\(url.lastPathComponent)")
            }
            .padding(.horizontal, 16).frame(height: 56)
        }
        .background(GlancePalette.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
            session.activeURL == url ? GlancePalette.accent : GlancePalette.divider(colorScheme), lineWidth: 1))
    }

    private func zoomLabel(for url: URL) -> String {
        let zoom = session.transform(for: url).zoom
        let percent = Int((zoom * 100).rounded())
        return abs(zoom - 1) < 0.005 ? "适应窗口 · 100%" : "\(percent)%"
    }

    private func exitComparison() {
        if let url = session.activeURL, let index = appState.imageFiles.firstIndex(of: url) {
            appState.selectSingleImage(index: index)
        }
    }

    /// Shows the focused photo at 100% of its real pixels (the others follow when zoom is linked).
    private func showActualSize() {
        guard let url = session.activeURL, let image = store.image(for: url), image.size.width > 0, image.size.height > 0,
              imageAreaSize.width > 0 else { return }
        let fit = min(imageAreaSize.width / image.size.width, imageAreaSize.height / image.size.height)
        guard fit > 0 else { return }
        var value = session.transform(for: url)
        value.zoom = 1 / fit
        value.pan = .zero
        session.update(value, for: url)
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


/// Small rounded chip used for the compare screen's buttons (Paper: control fill, 8pt radius).
struct CompareChipStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(GlancePalette.secondary(colorScheme))
            .padding(.horizontal, 12)
            .frame(height: compact ? 30 : 32)
            .background(prominent ? GlancePalette.accentSoft(colorScheme) : GlancePalette.control(colorScheme),
                        in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(GlancePalette.fieldBorder(colorScheme), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
