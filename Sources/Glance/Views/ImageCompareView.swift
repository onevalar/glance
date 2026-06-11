//
//  ImageCompareView.swift
//  Glance
//

import SwiftUI

struct ImageCompareView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    // Shared magnification and offset bound to all subviews
    @State private var sharedMagnification: CGFloat = 1.0
    @State private var sharedOffset: CGPoint = .zero
    
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
                    ForEach(selectedUrls, id: \.self) { url in
                        VStack(spacing: 0) {
                            if let image = NSImage(contentsOf: url) {
                                ZoomableImageView(
                                    image: image,
                                    sharedMagnification: $sharedMagnification,
                                    sharedOffset: $sharedOffset,
                                    isShared: true
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
                .onChange(of: appState.selectedImageIndices) { _, _ in
                    // Reset shared state when selection changes
                    sharedMagnification = 1.0
                    sharedOffset = .zero
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
