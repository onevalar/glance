//
//  PhotoGridView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// Overview of the current photos.
/// - Browse: tap a photo to jump to it; "选择" starts picking.
/// - Compare picker (opened from the dock's 对比 button): the current photo is already selected,
///   tap 1–3 more, then press the big 开始对比 button.
struct PhotoGridView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let pickForCompare: Bool
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
                .padding(.bottom, selecting ? 110 : 0)
            }
            .background(GlancePalette.canvas(scheme))
            .overlay(alignment: .bottom) { if selecting { compareBar } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selecting && !pickForCompare {
                        Button("取消") { endSelecting() }
                    } else {
                        Button(pickForCompare ? "取消" : "完成") { dismiss() }
                            .accessibilityIdentifier("grid.close")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !selecting {
                        Button("选择") { selecting = true }
                            .accessibilityIdentifier("grid.select")
                    }
                }
            }
        }
        .onAppear {
            if pickForCompare, !selecting {
                selecting = true
                if let id = store.currentID { selected = [id] }
            }
        }
    }

    private var title: String {
        if selecting { return selected.isEmpty ? "选择要对比的照片" : "已选 \(selected.count) 张" }
        return "\(store.visible.count) 张照片"
    }

    /// Bottom glass panel: says what to do, and holds the one big action.
    private var compareBar: some View {
        VStack(spacing: 10) {
            Text(selected.count < 2 ? "再点 \(2 - selected.count) 张以上，最多选 4 张" : "已选 \(selected.count) 张，可以开始对比了")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button(action: startCompare) {
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

    private func startCompare() {
        let ids = selected
        dismiss()
        // Present after the grid has gone, otherwise SwiftUI drops the second cover.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onCompare(ids) }
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
