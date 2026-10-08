//
//  ThumbnailViews.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

struct ThumbnailCell: View {
    let asset: PHAsset
    let size: CGSize
    let isSelected: Bool

    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var status: ImageStatus {
        metadata.getMetadata(forKey: asset.localIdentifier).status
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 6))
            .opacity(status == .discard ? 0.4 : 1)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).stroke(GlancePalette.accent, lineWidth: 2)
                }
            }

            switch status {
            case .discard:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.system(size: 16))
                    .padding(4)
            case .keep:
                Image(systemName: "flag.circle.fill")
                    .foregroundStyle(.white, GlancePalette.accent)
                    .font(.system(size: 16))
                    .padding(4)
            case .undecided:
                EmptyView()
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: asset.localIdentifier) {
            image = await PhotoImageLoader.image(
                for: asset,
                targetSize: CGSize(width: size.width * displayScale, height: size.height * displayScale),
                contentMode: .aspectFill
            )
        }
    }
}

/// Filmstrip of the visible photos: horizontal on iPhone, a vertical column on iPad.
struct ThumbnailStrip: View {
    @EnvironmentObject private var store: LibraryStore
    let axis: Axis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cellSize: CGSize {
        axis == .horizontal ? CGSize(width: 52, height: 68) : CGSize(width: 112, height: 84)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                if axis == .horizontal {
                    LazyHStack(spacing: 6) { cells }
                        .padding(.horizontal, 12)
                } else {
                    LazyVStack(spacing: 10) { cells }
                        .padding(.vertical, 10)
                }
            }
            .onChange(of: store.currentID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { reader.scrollTo(id, anchor: .center) }
            }
            .onAppear {
                if let id = store.currentID { reader.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var cells: some View {
        ForEach(Array(store.visible.enumerated()), id: \.element.localIdentifier) { index, asset in
            Button { store.select(asset) } label: {
                ThumbnailCell(asset: asset, size: cellSize, isSelected: asset.localIdentifier == store.currentID)
            }
            .buttonStyle(.plain)
            .id(asset.localIdentifier)
            .accessibilityLabel("照片 \(index + 1)")
            .accessibilityValue(asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
            .accessibilityAddTraits(asset.localIdentifier == store.currentID ? .isSelected : [])
        }
    }
}
