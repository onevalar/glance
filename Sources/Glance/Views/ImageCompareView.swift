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
    @Environment(\.colorScheme) private var colorScheme
    
    // Zoom (relative to each picture's own fit) and pan (fraction of the zoomed picture)
    // shared by all cells; owned by ContentView so the toolbar can drive it too.
    @Binding var sharedZoom: CGFloat
    @Binding var sharedPan: CGPoint
    var onScaleChanged: ((CGFloat) -> Void)?
    
    var selectedUrls: [URL] {
        appState.selectedImageIndices.sorted().compactMap { index -> URL? in
            guard index >= 0 && index < appState.imageFiles.count else { return nil }
            return appState.imageFiles[index]
        }
    }
    
    var gridColumns: [GridItem] {
        let count = selectedUrls.count
        if count == 2 {
            return [GridItem(.flexible()), GridItem(.flexible())]
        } else if count == 3 {
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        } else if count == 4 {
            return [GridItem(.flexible()), GridItem(.flexible())]
        } else {
            // 5 or more
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if selectedUrls.isEmpty {
                VStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("未选中图片")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(Array(selectedUrls.enumerated()), id: \.element) { position, url in
                        VStack(spacing: 0) {
                            if let image = store.image(for: url) {
                                ZoomableImageView(
                                    image: image,
                                    sharedZoom: $sharedZoom,
                                    sharedPan: $sharedPan,
                                    isShared: true,
                                    // The toolbar percentage follows the first cell.
                                    onScaleChanged: position == 0 ? { scale in
                                        DispatchQueue.main.async { onScaleChanged?(scale) }
                                    } : nil
                                )
                                .frame(height: gridItemHeight(totalWidth: geometry.size.width, totalHeight: geometry.size.height))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                        .overlay {
                            // Subtitle of file name
                            VStack {
                                Spacer()
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .padding([.leading, .trailing], 6)
                                    .padding([.top, .bottom], 2)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(4)
                                    .padding(.bottom, 6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("open-image"))) { _ in
                    store.invalidate()
                }
                .onChange(of: appState.selectedImageIndices) { _, _ in
                    store.keep(selectedUrls)
                    // Reset shared state when selection changes
                    sharedZoom = 1.0
                    sharedPan = .zero
                }
            }
        }
    }
    
    private func gridItemHeight(totalWidth: CGFloat, totalHeight: CGFloat) -> CGFloat {
        let count = selectedUrls.count
        if count <= 2 {
            return totalHeight
        } else if count == 3 {
            return totalHeight
        } else if count == 4 {
            return totalHeight / 2 - 2
        } else {
            let rows = CGFloat(ceil(Double(count) / 3.0))
            return totalHeight / rows - 2
        }
    }
}
