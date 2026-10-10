//
//  PhotoGridView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// All photos of the current scope as a grid: tap one to jump to it. (Picking photos to compare is a separate screen.)
struct PhotoGridView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(store.visible, id: \.localIdentifier) { asset in
                            GridCell(
                                asset: asset,
                                meta: metadata.getMetadata(forKey: asset.localIdentifier),
                                isCurrent: asset.localIdentifier == store.currentID,
                                selectionIndex: nil,
                                selecting: false
                            )
                            .id(asset.localIdentifier)
                            .onTapGesture {
                                store.select(asset)
                                dismiss()
                            }
                        }
                    }
                    .padding(3)
                }
                .onAppear {
                    if let id = store.currentID { reader.scrollTo(id, anchor: .center) }
                }
            }
            .background(GlancePalette.canvas(scheme))
            .navigationTitle("\(store.visible.count) 张照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("grid.close")
                }
            }
        }
    }
}

/// Pick two or more photos (any number) to compare side by side. The current photo is already ticked.
struct ComparePickerView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var onCompare: ([String]) -> Void

    @State private var selected: [String] = []

    /// Comparing many shots at once is allowed; this only keeps memory in check.
    private static let maxCompare = 24

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(store.visible, id: \.localIdentifier) { asset in
                        GridCell(
                            asset: asset,
                            meta: metadata.getMetadata(forKey: asset.localIdentifier),
                            isCurrent: false,
                            selectionIndex: selected.firstIndex(of: asset.localIdentifier).map { $0 + 1 },
                            selecting: true
                        )
                        .onTapGesture { tap(asset) }
                    }
                }
                .padding(3)
                .padding(.bottom, 120)
            }
            .background(GlancePalette.canvas(scheme))
            .overlay(alignment: .bottom) { startBar }
            .navigationTitle(selected.isEmpty ? "选择要对比的照片" : "已选 \(selected.count) 张")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("grid.close")
                }
            }
        }
        .onAppear {
            if selected.isEmpty, let id = store.currentID { selected = [id] }
        }
    }

    private var startBar: some View {
        VStack(spacing: 10) {
            Text(selected.count < 2 ? "再点几张照片（至少 2 张，数量不限）" : "已选 \(selected.count) 张，可以开始对比了")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                let ids = selected
                dismiss()
                // Present after this screen has gone, otherwise SwiftUI drops the second cover.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onCompare(ids) }
            } label: {
                Label("开始对比（\(selected.count)）", systemImage: "rectangle.split.2x1")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected.count >= 2 ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(selected.count >= 2 ? GlancePalette.accent : Color.clear, in: .capsule)
                    .contentShape(.capsule)
                    .glassSurface(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(selected.count < 2)
            .accessibilityIdentifier("grid.compare")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassSurface(.rect(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func tap(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else if selected.count < Self.maxCompare {
            selected.append(id)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}

struct GridCell: View {
    let asset: PHAsset
    let meta: ImageMetadata
    let isCurrent: Bool
    let selectionIndex: Int?
    let selecting: Bool
    /// Tick-box selection (the discard pile): nil = no box, otherwise whether it is ticked.
    var checked: Bool? = nil
    /// The rating / discard badge (pointless inside the discard pile, where every photo is discarded).
    var showsBadge = true

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
            .overlay(alignment: .topTrailing) {
                if !showsBadge {
                    EmptyView()
                } else if meta.isDiscarded {
                    Image(systemName: "trash.circle.fill").foregroundStyle(.white, .red).font(.system(size: 22)).padding(4)
                } else if meta.rating > 0 {
                    Label("\(meta.rating)", systemImage: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.yellow, in: .capsule)
                        .padding(4)
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
            .overlay(alignment: .bottomTrailing) {
                if let checked {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(checked ? Color.white : Color.white.opacity(0.9), checked ? GlancePalette.accent : Color.black.opacity(0.25))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .padding(6)
                }
            }
            .overlay {
                if checked == true { Rectangle().strokeBorder(GlancePalette.accent, lineWidth: 3) }
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
            .accessibilityLabel("照片，\(meta.isDiscarded ? "已丢弃" : meta.rating > 0 ? "\(meta.rating) 星" : "未评分")")
            .accessibilityAddTraits(selectionIndex != nil || checked == true ? .isSelected : [])
    }
}
