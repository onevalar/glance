import AppKit
import SwiftUI

/// Floating action bar under the photo: ‹  丢弃 X | 待定 U | 保留 P  ›  裁剪 R (Paper: 01 · macOS 单图).
struct ToolBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @ObservedObject private var metadata = MetadataManager.shared

    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?

    private var current: ImageStatus? {
        appState.currentImageURL.map { metadata.getMetadata(for: $0).status }
    }

    var body: some View {
        HStack(spacing: 10) {
            barButton("‹", label: "上一张", disabled: appState.selectedImageIndex <= 0) {
                appState.navigateToPrevImage()
            }
            rating("丢弃 X", .discard)
            rating("待定 U", .undecided)
            rating("保留 P", .keep)
            barButton("›", label: "下一张", disabled: appState.selectedImageIndex >= appState.imageFiles.count - 1) {
                appState.navigateToNextImage()
            }
            barButton("裁剪 R", label: "裁剪", disabled: appState.currentImageURL == nil) {
                appState.isCropEditing = true
            }
        }
        .padding(10)
        .background(GlancePalette.control(colorScheme), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(GlancePalette.fieldBorder(colorScheme), lineWidth: 1) }
        .onHover { hovering in
            if hovering { onHoverEnter?() } else { onHoverExit?() }
        }
    }

    private func rating(_ title: String, _ status: ImageStatus) -> some View {
        barButton(title, label: LocalizedStringKey(status.title), active: current == status) {
            appState.setStatusForSelectedImages(status)
        }
        .accessibilityAddTraits(current == status ? .isSelected : [])
    }

    private func barButton(_ title: String, label: LocalizedStringKey, active: Bool = false,
                           disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GlancePalette.secondary(colorScheme))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(active ? GlancePalette.accentSoft(colorScheme) : GlancePalette.buttonFill(colorScheme),
                            in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(Text(label))
    }
}
