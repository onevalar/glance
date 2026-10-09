//
//  GestureGuide.swift
//  Glance (iPhone / iPad)
//

import SwiftUI

/// First-launch (and on demand) explanation of the gestures; there are no on-screen rating buttons.
struct GestureGuide: View {
    @Environment(\.colorScheme) private var scheme
    var starScale = 5
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.9)).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 22) {
                Text("这样筛选照片")
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.bottom, 4)

                row("star.fill", .yellow, "往上滑，出现 \(starScale) 颗星", "手指停在第几颗，松手就是几星")
                row("trash", .red, "往下拉，垃圾桶升起", "拖进去松手就是丢弃，不会立刻删除")
                row("arrow.left.and.right", .white, "左右滑动", "切换照片")
                row("plus.magnifyingglass", .white, "双击或双指张开", "放大看细节")
                row("rectangle.split.2x1", .white, "底部“对比”", "选几张相似的照片，并排放大对比")

                Text("评错了？点屏幕下方的“撤销”。丢弃的照片可以随时在“筛选 → 已丢弃”里找回，最后再统一删除。")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))

                Button(action: onDismiss) {
                    Text("开始筛选")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(GlancePalette.accent, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guide.start")
            }
            .foregroundStyle(.white)
            .padding(28)
            .frame(maxWidth: 420)
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ symbol: String, _ tint: Color, _ gesture: String, _ meaning: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(gesture).font(.system(size: 16, weight: .semibold))
                Text(meaning).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}
