//
//  ThumbnailSidebar.swift
//  Glance
//

import SwiftUI

struct ThumbnailSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState

    let windowHeight: CGFloat
    @State private var showingBulkClearAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Top Filter and Clear Bar
            HStack(spacing: 8) {
                // Filter Menu
                Menu {
                    ForEach(PhotoFilter.allCases) { filter in
                        Button(action: {
                            appState.activeFilter = filter
                            appState.updateFilteredImages(preserveSelection: true)
                            NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
                        }) {
                            HStack {
                                Text(filter.rawValue)
                                if appState.activeFilter == filter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.activeFilter.iconName)
                            .foregroundColor(.secondary)
                        Text(appState.activeFilter.rawValue)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                // Bulk Clear Discard Button
                Button(action: {
                    showingBulkClearAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("一键清空丢弃的照片")
                .disabled(appState.allImageFiles.filter { MetadataManager.shared.getMetadata(for: $0).status == .discard }.isEmpty)
            }
            .padding([.leading, .trailing], 12)
            .padding([.top, .bottom], 10)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.85))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    .frame(height: 1)
            }
            
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(appState.imageFiles.enumerated()), id: \.offset) { index, imageURL in
                            ImageThumbnailView(
                                imageURL: imageURL,
                                isSelected: appState.selectedImageIndex == index,
                                isMultiSelected: appState.selectedImageIndices.contains(index)
                            )
                            .id(index)
                            .onTapGesture {
                                handleTap(at: index)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .padding([.top, .bottom], 8)
                .padding([.leading, .trailing], 8)
                .onAppear { scroller.scrollTo(appState.selectedImageIndex) }
                .onChange(of: appState.selectedImageIndex) { _, new in scroller.scrollTo(new) }
            }
        }
        .padding([.top], 24)
        .frame(width: 144, height: windowHeight)
        .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.gray.opacity(0.3))
                .frame(width: 1)
        }
        .alert("清空丢弃的照片", isPresented: $showingBulkClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                appState.bulkMoveDiscardedToTrash()
            }
        } message: {
            let count = appState.allImageFiles.filter { MetadataManager.shared.getMetadata(for: $0).status == .discard }.count
            Text("确定要将这 \(count) 张标记为“丢弃”的图片移动到系统废纸篓吗？此操作不可撤销。")
        }
    }
    
    private func handleTap(at index: Int) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            appState.toggleImageSelection(index: index)
        } else if flags.contains(.shift) {
            appState.selectRangeOfImages(toIndex: index)
        } else {
            appState.selectSingleImage(index: index)
        }
        NotificationCenter.default.post(name: Notification.Name("open-image"), object: nil)
    }
}
