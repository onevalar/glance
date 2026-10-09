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
    @AppStorage("didShowCompareHint") private var didShowHint = false
    @State private var showHint = false

    private var assets: [PHAsset] { assetIDs.compactMap { store.asset(withID: $0) } }

    var body: some View {
        // The geometry respects the safe areas, so the photos start below the status bar / top bar
        // and end above the home indicator.
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                layout(in: proxy.size)
                    .padding(.top, 52)
                topBar
                if showHint {
                    VStack {
                        Spacer()
                        compareHint
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }
            }
        }
        .background(GlancePalette.canvas(scheme).ignoresSafeArea())
        .onAppear {
            focusedID = assetIDs.first
            if !didShowHint { withAnimation { showHint = true } }
        }
    }

    private var topBar: some View {
        GlassGroup(spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                        .glassSurface(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭对比")
                .accessibilityIdentifier("compare.close")
                Spacer()
                Text("对比 · \(assets.count) 张")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .glassSurface(.capsule)
                Spacer()
                Button {
                    synced.toggle()
                    hub.isEnabled = synced
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: synced ? "link" : "link.badge.plus")
                        Text(synced ? "同步" : "各自")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(synced ? GlancePalette.accent : Color.primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(.capsule)
                    .glassSurface(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("同步缩放")
                .accessibilityValue(synced ? "开启" : "关闭")
                .accessibilityIdentifier("compare.sync")
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    /// One-time explanation of what this screen can do.
    private var compareHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("两指张开放大任意一张，其他几张会一起移到同一处", systemImage: "hand.pinch")
            Label("点每张下面的“丢弃 / 保留”直接打分", systemImage: "flag")
            Label("右上角“同步”可以改成各看各的", systemImage: "link")
            Button("知道了") {
                didShowHint = true
                withAnimation { showHint = false }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(GlancePalette.accent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("compare.hint.ok")
        }
        .font(.system(size: 13))
        .padding(16)
        // Solid surface instead of glass: this is text that must stay readable on any photo.
        .background(GlancePalette.surface(scheme), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(GlancePalette.fieldBorder(scheme), lineWidth: 1) }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
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
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassSurface(.capsule)
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
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(on ? (target == .keep ? Color.green : Color.red) : Color.clear, in: .capsule)
                .contentShape(.capsule)
                .glassSurface(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compare.\(target.rawValue).\(asset.localIdentifier)")
    }
}
