//
//  ImageThumbnailView.swift
//  Glance
//

import SwiftUI

/// One photo card in the sidebar: picture, file name and rating (Paper: "01 · macOS 单图").
struct ImageThumbnailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var metadataManager = MetadataManager.shared

    let imageURL: URL
    let isSelected: Bool
    let isMultiSelected: Bool

    @State private var thumbnail: NSImage?

    private var status: ImageStatus {
        metadataManager.getMetadata(for: imageURL).status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(GlancePalette.buttonFill(colorScheme))
                        .overlay { Image(systemName: "photo").foregroundStyle(GlancePalette.muted(colorScheme)) }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 103)
            .clipShape(.rect(cornerRadius: 4))
            .opacity(status == .discard ? 0.4 : 1)

            HStack(spacing: 8) {
                Text(imageURL.lastPathComponent)
                    .foregroundStyle(GlancePalette.secondary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(status.title)
                    .foregroundStyle(status == .keep ? GlancePalette.foreground(colorScheme) : GlancePalette.muted(colorScheme))
                    .fixedSize()
            }
            .font(.system(size: 12))
        }
        .padding(8)
        .background(isMultiSelected ? GlancePalette.accentSoft(colorScheme) : .clear, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected || isMultiSelected ? GlancePalette.accent : GlancePalette.divider(colorScheme), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 8))
        .task(id: imageURL) {
            // The card can be reused for another file after a deletion; never show the old picture.
            thumbnail = nil
            thumbnail = await ThumbnailCache.thumbnail(for: imageURL, maxPixelSize: 480)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("open-image"))) { _ in
            // Rotation and crop post this after rewriting the file; reload so the sidebar follows.
            Task { thumbnail = await ThumbnailCache.thumbnail(for: imageURL, maxPixelSize: 480) }
        }
    }
}
