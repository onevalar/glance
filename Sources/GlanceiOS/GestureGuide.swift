//
//  GestureGuide.swift
//  Glance (iPhone / iPad)
//

import SwiftUI

/// First-launch (and on demand) explanation of the gestures; there are no on-screen rating buttons.
struct GestureGuide: View {
    @Environment(\.colorScheme) private var scheme
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.9)).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 22) {
                Text("这样筛选照片")
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.bottom, 4)

                row("arrow.up", .green, "上滑，或点底部“保留”", "保留这张")
                row("arrow.down", .red, "下滑，或点底部“丢弃”", "丢弃这张")
                row("arrow.left.and.right", .white, "左右滑动", "切换照片")
                row("plus.magnifyingglass", .white, "双击或双指张开", "放大看细节")
                row("rectangle.split.2x1", .white, "底部“对比”", "选 2–4 张相似的照片，并排放大对比")

                Text("标错了？再滑一次同方向取消，或点提示条上的“撤销”。")
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
