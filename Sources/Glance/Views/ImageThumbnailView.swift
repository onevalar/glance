//
//  ImageThumbnailView.swift
//  Glance
//

import SwiftUI

struct ImageThumbnailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var metadataManager = MetadataManager.shared

    let imageURL: URL
    let isSelected: Bool
    let isMultiSelected: Bool

    @State private var thumbnail: NSImage?

    private var highlightColor: Color {
        colorScheme == .dark ? Color.yellow : Color.blue
    }
    
    private var metadata: ImageMetadata {
        metadataManager.getMetadata(for: imageURL)
    }

    var body: some View {
        let isDiscarded = metadata.status == .discard
        let isKeep = metadata.status == .keep
        
        ZStack(alignment: .topTrailing) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 90)
                    .clipShape(.rect(cornerRadius: 4))
                    .opacity(isDiscarded ? 0.4 : 1.0)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(highlightColor, lineWidth: 3)
                        } else if isMultiSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(highlightColor.opacity(0.5), lineWidth: 3)
                                .background(highlightColor.opacity(0.2))
                        }
                    }
                    .scaleEffect(isSelected ? 1.06 : 1.0)
                    .shadow(color: isSelected ? .black.opacity(colorScheme == .dark ? 0.25 : 0.15) : .clear, radius: 6, x: 0, y: 3)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            } else {
                // Placeholder while loading, or when the file cannot be decoded.
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, height: 90)
                    .background(Color.clear)
                    .opacity(isDiscarded ? 0.4 : 1.0)
            }
            
            // Status Badge Overlay
            if isDiscarded {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white).frame(width: 14, height: 14))
                    .font(.system(size: 16))
                    .padding([.top, .trailing], 6)
            } else if isKeep {
                Image(systemName: "flag.fill")
                    .foregroundColor(.green)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 12, height: 12))
                    .font(.system(size: 14))
                    .padding([.top, .trailing], 6)
            }
        }
        .frame(width: 120, height: 90)
        .task(id: imageURL) {
            // The view can be reused for another file after a deletion; never show the old picture.
            thumbnail = nil
            thumbnail = await ThumbnailCache.thumbnail(for: imageURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("open-image"))) { _ in
            // Rotation and crop post this after rewriting the file; reload so the sidebar follows.
            Task { thumbnail = await ThumbnailCache.thumbnail(for: imageURL) }
        }
    }
}
