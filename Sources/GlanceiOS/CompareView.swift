//
//  CompareView.swift
//  Glance (iPhone / iPad)
//

import Photos
import SwiftUI

/// Two to four photos side by side. Zooming or panning one moves the others to the same spot
/// (relative to each photo's own size), so focus and detail can be compared directly.
struct CompareView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let assetIDs: [String]

    @State private var hub = CompareSyncHub()
    @State private var synced = true
    @State private var focusedID: String?

    private var assets: [PHAsset] { assetIDs.compactMap { store.asset(withID: $0) } }

    var body: some View {
        // The geometry respects the safe areas, so the photos start below the status bar / top bar
        // and end above the home indicator.
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                layout(in: proxy.size)
                    .padding(.top, 48)
                topBar
            }
        }
        .background(GlancePalette.canvas(scheme).ignoresSafeArea())
        .onAppear { focusedID = assetIDs.first }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("关闭对比")
            .accessibilityIdentifier("compare.close")
            Spacer()
            Text("对比 · \(assets.count) 张").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                synced.toggle()
                hub.isEnabled = synced
            } label: {
                Image(systemName: synced ? "link" : "link.badge.plus")
                    .foregroundStyle(synced ? GlancePalette.accent : GlancePalette.muted(scheme))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("同步缩放")
            .accessibilityValue(synced ? "开启" : "关闭")
        }
        .foregroundStyle(GlancePalette.foreground(scheme))
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(GlancePalette.surface(scheme))
        .background(alignment: .top) { GlancePalette.surface(scheme).ignoresSafeArea(edges: .top) }
    }

    @ViewBuilder
    private func layout(in size: CGSize) -> some View {
        let landscape = size.width > size.height
        let list = assets
        switch list.count {
        case 2:
            stack(landscape ? .horizontal : .vertical, list)
        case 3 where landscape:
            stack(.horizontal, list)
        case 3:
            VStack(spacing: 3) {
                cell(list[0])
                HStack(spacing: 3) { cell(list[1]); cell(list[2]) }
            }
        default:
            VStack(spacing: 3) {
                HStack(spacing: 3) { cell(list[0]); cell(list[1]) }
                HStack(spacing: 3) {
                    if list.count > 2 { cell(list[2]) }
                    if list.count > 3 { cell(list[3]) }
                }
            }
        }
    }

    @ViewBuilder
    private func stack(_ axis: Axis, _ list: [PHAsset]) -> some View {
        if axis == .horizontal {
            HStack(spacing: 3) { ForEach(list, id: \.localIdentifier) { cell($0) } }
        } else {
            VStack(spacing: 3) { ForEach(list, id: \.localIdentifier) { cell($0) } }
        }
    }

    private func cell(_ asset: PHAsset) -> some View {
        CompareCell(
            asset: asset,
            hub: hub,
            isFocused: focusedID == asset.localIdentifier,
            onFocus: { focusedID = asset.localIdentifier }
        )
    }
}

private struct CompareCell: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @Environment(\.colorScheme) private var scheme

    let asset: PHAsset
    let hub: CompareSyncHub
    let isFocused: Bool
    var onFocus: () -> Void

    private var status: ImageStatus { metadata.getMetadata(forKey: asset.localIdentifier).status }

    var body: some View {
        ZStack {
            PhotoPage(asset: asset, ratingGesturesEnabled: false, syncHub: hub, onSingleTap: onFocus)

            VStack {
                HStack {
                    Text(store.displayName(of: asset))
                        .font(.system(size: 12))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: .capsule)
                    Spacer()
                }
                Spacer()
                HStack(spacing: 8) {
                    chip("丢弃", .discard)
                    chip("保留", .keep)
                }
            }
            .padding(8)
        }
        .clipped()
        .overlay {
            Rectangle().strokeBorder(isFocused ? GlancePalette.accent : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ title: String, _ target: ImageStatus) -> some View {
        let on = status == target
        return Button {
            store.setStatus(target, forAssetID: asset.localIdentifier)
        } label: {
            Text(on ? (target == .keep ? "已保留" : "已丢弃") : title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? .white : GlancePalette.secondary(scheme))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(on ? (target == .keep ? Color.green : Color.red).opacity(0.9) : Color.clear, in: .capsule)
                .background(.regularMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compare.\(target.rawValue).\(asset.localIdentifier)")
    }
}
