//
//  ImageInfoPanel.swift
//  Glance
//

import SwiftUI

/// Right-hand "文件信息" panel (Paper: 260pt wide, docked).
struct ImageInfoPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var metadata = MetadataManager.shared

    let imageURL: URL?

    private var rows: [(String, String)] {
        guard let url = imageURL else { return [] }
        var pixels = "—"
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            pixels = "\(width) × \(height)"
        }
        return [
            (String(localized: "文件名"), url.lastPathComponent),
            (String(localized: "尺寸"), pixels),
            (String(localized: "格式"), url.pathExtension.uppercased()),
            (String(localized: "所在位置"), url.deletingLastPathComponent().lastPathComponent),
            (String(localized: "评分"), ratingText(metadata.getMetadata(for: url))),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("文件信息")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GlancePalette.foreground(colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(rows, id: \.0) { label, value in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(label)
                                .font(.system(size: 12))
                                .foregroundStyle(GlancePalette.muted(colorScheme))
                            Text(value)
                                .font(.system(size: 15))
                                .foregroundStyle(GlancePalette.foreground(colorScheme))
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(GlancePalette.divider(colorScheme)).frame(height: 1)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Text("← → 切换图片\n滚轮缩放 · 拖动平移\n5 秒无操作后工具栏隐藏")
                        .font(.system(size: 13))
                        .foregroundStyle(GlancePalette.muted(colorScheme))
                        .lineSpacing(4)
                }
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(GlancePalette.inspector(colorScheme))
        .overlay(alignment: .leading) {
            Rectangle().fill(GlancePalette.divider(colorScheme)).frame(width: 1)
        }
    }

    private func ratingText(_ meta: ImageMetadata) -> String {
        if meta.isDiscarded { return "已丢弃" }
        if meta.rating == 0 { return "未评分" }
        return String(repeating: "★", count: meta.rating) + String(repeating: "☆", count: max(0, 5 - meta.rating))
    }
}
