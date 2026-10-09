import AppKit
import SwiftUI

/// Floating action bar under the photo: ‹  丢弃 X | ★★★★★ (1–5) |  ›  裁剪 R.
struct ToolBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @ObservedObject private var metadata = MetadataManager.shared
    @AppStorage("starScale") private var starScale = 5

    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?

    private var current: ImageMetadata {
        appState.currentImageURL.map { metadata.getMetadata(for: $0) } ?? ImageMetadata()
    }

    var body: some View {
        HStack(spacing: 10) {
            barButton("‹", label: "上一张", disabled: appState.selectedImageIndex <= 0) {
                appState.navigateToPrevImage()
            }
            barButton("丢弃 X", label: "丢弃", active: current.isDiscarded, activeFill: Color.red.opacity(0.22)) {
                appState.toggleDiscardForSelectedImages()
            }
            stars
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

    /// Clickable stars; keys 1…5 do the same, 0 clears.
    private var stars: some View {
        HStack(spacing: 2) {
            ForEach(1...starScale, id: \.self) { index in
                Button {
                    appState.rateSelectedImages(stars: index)
                } label: {
                    Image(systemName: index <= current.rating ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(index <= current.rating ? Color.yellow : GlancePalette.secondary(colorScheme))
                        .frame(width: 26, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(index) 星（按 \(index)）")
                .accessibilityLabel("\(index) 星")
                .accessibilityAddTraits(index == current.rating ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .background(GlancePalette.buttonFill(colorScheme), in: .rect(cornerRadius: 8))
    }

    private func barButton(_ title: String, label: LocalizedStringKey, active: Bool = false,
                           activeFill: Color? = nil, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GlancePalette.secondary(colorScheme))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(active ? (activeFill ?? GlancePalette.accentSoft(colorScheme)) : GlancePalette.buttonFill(colorScheme),
                            in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(Text(label))
    }
}
