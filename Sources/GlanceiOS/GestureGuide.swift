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

                row("star.fill", .yellow, "往上滑，星星升起", "手指移到哪颗星、在那里松手，就评几星；松手时不在星星上＝取消")
                row("trash", .red, "往下拉，垃圾桶升起", "拖到垃圾桶松手＝丢弃，不会立刻删除")
                row("arrow.left.and.right", .white, "左右滑动", "切换照片，点一下照片隐藏所有按钮")
                row("plus.magnifyingglass", .white, "双击或双指张开", "放大看细节")
                row("rectangle.split.2x1", .white, "底部“对比”", "选几张相似的照片，并排放大对比")

                Text("底部的垃圾桶和星星按钮与手势作用相同。评错了点“撤销”。丢弃的照片在左上“全部照片”旁的筛选里随时可找回，最后再统一删除。")
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
