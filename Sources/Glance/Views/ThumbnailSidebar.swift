//
//  ThumbnailSidebar.swift
//  Glance
//

import SwiftUI

/// Left column: folder name, rating filter and photo cards (Paper: 208pt wide).
struct ThumbnailSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @ObservedObject private var metadata = MetadataManager.shared

    @Binding var isSearching: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(appState.folderName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GlancePalette.foreground(colorScheme))
                .lineLimit(1)

            filterMenu

            if isSearching {
                searchField
            }

            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(Array(appState.imageFiles.enumerated()), id: \.element) { index, imageURL in
                            ImageThumbnailView(
                                imageURL: imageURL,
                                isSelected: appState.selectedImageIndex == index,
                                isMultiSelected: appState.selectedImageIndices.count > 1 && appState.selectedImageIndices.contains(index)
                            )
                            .id(index)
                            .onTapGesture { handleTap(at: index) }
                            .contextMenu {
                                Button(appState.selectedImageIndices.count > 1 && appState.selectedImageIndices.contains(index) ? "移出比较" : "加入比较") {
                                    appState.toggleImageSelection(index: index)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(imageURL.lastPathComponent)
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .onAppear { scroller.scrollTo(appState.selectedImageIndex) }
                .onChange(of: appState.selectedImageIndex) { _, new in scroller.scrollTo(new) }
            }
        }
        .padding(16)
        .frame(width: 208)
        .frame(maxHeight: .infinity)
        .background(GlancePalette.surface(colorScheme))
        .overlay(alignment: .trailing) {
            Rectangle().fill(GlancePalette.divider(colorScheme)).frame(width: 1)
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(PhotoFilter.allCases) { filter in
                Button {
                    appState.activeFilter = filter
                    appState.updateFilteredImages(preserveSelection: true)
                } label: {
                    Text("\(filter.rawValue) \(appState.count(for: filter))")
                    if appState.activeFilter == filter { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("\(appState.activeFilter.rawValue) \(appState.imageFiles.count)")
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 6))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(GlancePalette.secondary(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(GlancePalette.buttonFill(colorScheme), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("筛选")
        .accessibilityValue("\(appState.activeFilter.rawValue) \(appState.imageFiles.count)")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(GlancePalette.muted(colorScheme))
            TextField("按文件名搜索", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
            if !appState.searchText.isEmpty {
                Button { appState.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        .foregroundStyle(GlancePalette.muted(colorScheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(GlancePalette.buttonFill(colorScheme), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(GlancePalette.fieldBorder(colorScheme), lineWidth: 1) }
        .onAppear { searchFocused = true }
        .onExitCommand {
            appState.searchText = ""
            isSearching = false
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
    }
}
