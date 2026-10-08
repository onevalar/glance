import AppKit
import SwiftUI

struct ToolBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    let scale: CGSize
    let onTap: (_ actionID: ToolbarActionIdentifier) -> Void
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?

    private var comparing: Bool { appState.selectedImageIndices.count > 1 }
    private var hasImage: Bool { appState.currentImageURL != nil }
    var body: some View {
        HStack(spacing: 4) {
            control("sidebar.left", title: "Toggle navigation", action: .toggleNav)
            separator
            control("minus", title: "Zoom out", action: .scaleMinis)
            Text(scale.width, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 43)
                .accessibilityLabel(Text("缩放比例"))
            control("plus", title: "Zoom in", action: .scalePlus)
            control("arrow.up.left.and.arrow.down.right", title: "Fit to window", action: .centerFill)
            separator
            control("chevron.left", title: "Previous picture", action: .showPrev,
                    disabled: appState.selectedImageIndex <= 0)
            Text("\(appState.selectedImageIndex + 1) / \(appState.imageFiles.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary).frame(minWidth: 47)
            control("chevron.right", title: "Next picture", action: .showNext,
                    disabled: appState.selectedImageIndex >= appState.imageFiles.count - 1)
            separator
            control("arrow.counterclockwise", title: "Rotate left", action: .rotateLeft, disabled: comparing)
            control("arrow.clockwise", title: "Rotate right", action: .rotateRight, disabled: comparing)
            control("trash", title: "Delete Picture", action: .deleteImage, disabled: comparing)
            separator
            control("info.circle", title: "Picture info", action: .toggleInfo)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(GlancePalette.raised(colorScheme), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(GlancePalette.border(colorScheme), lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 12, y: 4)
        .onHover { hovering in
            if hovering { onHoverEnter?() } else { onHoverExit?() }
        }
    }
    private var separator: some View { Divider().frame(height: 16).padding(.horizontal, 6) }
    private func control(_ symbol: String, title: LocalizedStringKey, action: ToolbarActionIdentifier,
                         disabled: Bool = false) -> some View {
        Button { onTap(action) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular))
                .frame(width: 28, height: 28).contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .disabled(disabled || !hasImage)
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

enum ToolbarActionIdentifier: String, Hashable {
    case scaleMinis, scalePlus, showPrev, showNext, toggleNav, toggleInfo, centerFill
    case rotateLeft, rotateRight, deleteImage
}
