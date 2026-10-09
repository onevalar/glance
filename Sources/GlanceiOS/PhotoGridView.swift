//
//  PhotoGridView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// Overview of the current photos. Tap one to jump to it; "选择" (or a long press) picks 2–4 similar
/// shots to compare side by side.
struct PhotoGridView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var onCompare: ([String]) -> Void

    @State private var selecting = false
    @State private var selected: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(store.visible, id: \.localIdentifier) { asset in
                        GridCell(
                            asset: asset,
                            status: metadata.getMetadata(forKey: asset.localIdentifier).status,
                            isCurrent: asset.localIdentifier == store.currentID,
                            selectionIndex: selected.firstIndex(of: asset.localIdentifier).map { $0 + 1 },
                            selecting: selecting
                        )
                        .onTapGesture { tap(asset) }
                        .onLongPressGesture(minimumDuration: 0.35) { beginSelecting(with: asset) }
                    }
                }
                .padding(3)
            }
            .background(GlancePalette.canvas(scheme))
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    Text(selected.count < 2 ? "选 2–4 张相似的照片，再点右上角“对比”" : "已选 \(selected.count) 张，最多 4 张")
                        .font(.system(size: 13))
                        .foregroundStyle(GlancePalette.muted(scheme))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
            }
            .navigationTitle(selecting ? "已选 \(selected.count) 张" : "\(store.visible.count) 张照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selecting {
                        Button("取消") { endSelecting() }
                    } else {
                        Button("完成") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if selecting {
                        Button("对比") {
                            let ids = selected
                            dismiss()
                            // Present after the grid has gone, otherwise SwiftUI drops the second cover.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onCompare(ids) }
                        }
                        .disabled(selected.count < 2)
                        .accessibilityIdentifier("grid.compare")
                    } else {
                        Button("选择") { selecting = true }
                            .accessibilityIdentifier("grid.select")
                    }
                }
            }
        }
    }

    private func tap(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if selecting {
            if let index = selected.firstIndex(of: id) {
                selected.remove(at: index)
            } else if selected.count < 4 {
                selected.append(id)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        } else {
            store.select(asset)
            dismiss()
        }
    }

    private func beginSelecting(with asset: PHAsset) {
        guard !selecting else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selecting = true
        selected = [asset.localIdentifier]
    }

    private func endSelecting() {
        selecting = false
        selected = []
    }
}

private struct GridCell: View {
    let asset: PHAsset
    let status: ImageStatus
    let isCurrent: Bool
    let selectionIndex: Int?
    let selecting: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .clipped()
            .opacity(status == .discard ? 0.45 : 1)
            .overlay(alignment: .topTrailing) {
                switch status {
                case .keep:
                    Image(systemName: "flag.circle.fill").foregroundStyle(.white, .green).font(.system(size: 20)).padding(4)
                case .discard:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .red).font(.system(size: 20)).padding(4)
                case .undecided:
                    EmptyView()
                }
            }
            .overlay {
                if isCurrent && !selecting {
                    Rectangle().strokeBorder(GlancePalette.accent, lineWidth: 3)
                }
                if let selectionIndex {
                    Rectangle().strokeBorder(GlancePalette.accent, lineWidth: 3)
                    VStack {
                        Spacer()
                        HStack {
                            Text("\(selectionIndex)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(GlancePalette.accent, in: .circle)
                                .padding(6)
                            Spacer()
                        }
                    }
                }
            }
            .contentShape(.rect)
            .task(id: asset.localIdentifier) {
                image = await PhotoImageLoader.image(
                    for: asset,
                    targetSize: CGSize(width: 220 * displayScale, height: 220 * displayScale),
                    contentMode: .aspectFill
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("照片，\(status.title)")
            .accessibilityAddTraits(selectionIndex != nil ? .isSelected : [])
    }
}
