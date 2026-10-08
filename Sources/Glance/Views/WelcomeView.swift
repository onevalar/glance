import SwiftUI

struct WelcomeView: View {
    @ObservedObject var recents: RecentLocationStore
    let onChoose: () -> Void
    let onOpenRecent: (RecentLocationStore.Entry) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content.frame(minHeight: geometry.size.height)
            }
            .background(GlancePalette.raised(colorScheme))
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("过目").font(.system(size: 13, weight: .medium))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: Constants.settingsWindowID) } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Preferences...")
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: "photo")
                .font(.system(size: 42, weight: .light))
                .padding(.bottom, 30)
            Text("好照片，值得再看一眼。")
                .font(.system(size: 30, weight: .semibold))
            Text("拖入照片或文件夹，开始浏览与挑选。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Button(action: onChoose) {
                Label("打开照片…", systemImage: "plus")
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 24)

            if !recents.entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近打开").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    ForEach(recents.entries.prefix(3)) { entry in
                        Button { onOpenRecent(entry) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.isDirectory ? "folder" : "photo")
                                    .font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(entry.imageCount) 张照片")
                                        Text("·")
                                        Text(entry.openedAt, format: .dateTime.month().day())
                                    }
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { GlancePalette.border(colorScheme).frame(height: 1) }
                    }
                }
                .frame(maxWidth: 460)
                .padding(.top, 38)
            }
            Spacer(minLength: 24)
            Text("PNG、JPEG、GIF、WebP · ⌘ O 打开照片")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}
