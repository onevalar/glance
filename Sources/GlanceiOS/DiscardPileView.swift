//
//  DiscardPileView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// The discard pile at a glance (like Photos' "Recently Deleted"): every discarded photo of the library in a grid.
/// Restore or delete all of them, or pick some with 选择. Tapping a photo opens it large in the viewer.
/// Nothing leaves the library until it is deleted here (and then it goes to "Recently Deleted" for 30 days).
struct DiscardPileView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// Shows one photo of the pile in the viewer.
    var onOpen: (PHAsset) -> Void

    @State private var assets: [PHAsset] = []
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var notice: String?
    @State private var working = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty { emptyState } else { grid }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlancePalette.canvas(scheme))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("pile.close")
                }
                if !assets.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(selecting ? "取消" : "选择") {
                            selecting.toggle()
                            selected = []
                        }
                        .accessibilityIdentifier("pile.select")
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: store.pileCount) { _, _ in reload() }
    }

    private var title: String {
        guard selecting else { return "丢弃篮" }
        return selected.isEmpty ? "选择照片" : "已选 \(selected.count) 张"
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            Text("这 \(assets.count) 张照片还在你的相册里。删除后会移到相册的“最近删除”，30 天内仍可找回。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("pile.summary")
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    let id = asset.localIdentifier
                    GridCell(
                        asset: asset,
                        meta: metadata.getMetadata(forKey: id),
                        isCurrent: false,
                        selectionIndex: nil,
                        selecting: selecting,
                        checked: selecting ? selected.contains(id) : nil,
                        showsBadge: false
                    )
                    .onTapGesture { tap(asset) }
                }
            }
            .padding(3)
            .padding(.bottom, 120)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let notice {
                    Text(notice)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .glassSurface(.capsule)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                actionBar
            }
            .padding(.bottom, 8)
        }
    }

    /// 恢复 / 删除 for everything, or for the ticked photos while choosing.
    private var actionBar: some View {
        let ids = selecting ? assets.map(\.localIdentifier).filter(selected.contains) : assets.map(\.localIdentifier)
        let count = ids.count
        return HStack(spacing: 0) {
            Button { restore(ids) } label: {
                Label(selecting ? "恢复 \(count) 张" : "全部恢复", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pile.restore")

            Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 26)

            Button { delete(ids) } label: {
                Label(selecting ? "删除 \(count) 张" : "全部删除", systemImage: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pile.delete")
        }
        .disabled(count == 0 || working)
        .opacity(count == 0 ? 0.45 : 1)
        .padding(.horizontal, 6)
        .glassSurface(.capsule)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("丢弃篮是空的", systemImage: "trash")
        } description: {
            Text("看照片时往下拉，就能把它丢进来。删除之前，随时可以在这里找回。")
        } actions: {
            Button("完成") { dismiss() }
        }
        .accessibilityIdentifier("pile.empty")
    }

    // MARK: - Actions

    private func reload() {
        assets = store.pileAssets()
        selected = selected.filter { id in assets.contains { $0.localIdentifier == id } }
        if assets.isEmpty { selecting = false }
    }

    private func tap(_ asset: PHAsset) {
        let id = asset.localIdentifier
        guard selecting else {
            onOpen(asset)
            dismiss()
            return
        }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func restore(_ ids: [String]) {
        store.restore(ids)
        selecting = false
        selected = []
        reload()
        show("已恢复 \(ids.count) 张")
    }

    private func delete(_ ids: [String]) {
        let targets = assets.filter { ids.contains($0.localIdentifier) }
        working = true
        Task {
            // The system asks for confirmation itself; declining deletes nothing.
            let deleted = await store.delete(targets)
            working = false
            guard deleted else { return }
            selecting = false
            selected = []
            reload()
            show("已删除 \(targets.count) 张，可在相册的“最近删除”里找回")
        }
    }

    private func show(_ text: String) {
        withAnimation(.spring(duration: 0.25)) { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if notice == text { withAnimation { notice = nil } }
        }
    }
}
