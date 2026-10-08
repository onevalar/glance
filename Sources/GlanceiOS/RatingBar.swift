//
//  RatingBar.swift
//  Glance (iPhone / iPad)
//

import SwiftUI

/// The three culling buttons. Shortcuts match the Mac app (1 / 2 / 3, X / U / P) for hardware keyboards.
struct RatingBar: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var metadata = MetadataManager.shared
    @AppStorage("autoAdvance") private var autoAdvance = true
    @Environment(\.colorScheme) private var scheme

    private var current: ImageStatus? {
        store.currentID.map { metadata.getMetadata(forKey: $0).status }
    }

    var body: some View {
        HStack(spacing: 10) {
            button(.discard, title: "丢弃", icon: "xmark", keys: ("1", "x"))
            button(.undecided, title: "待定", icon: "questionmark", keys: ("2", "u"))
            button(.keep, title: "保留", icon: "flag.fill", keys: ("3", "p"))
        }
    }

    private func button(
        _ status: ImageStatus,
        title: String,
        icon: String,
        keys: (Character, Character)
    ) -> some View {
        let isOn = current == status
        return Button {
            store.rate(status, advance: autoAdvance)
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(status == .keep ? (isOn ? .white : GlancePalette.accent) : .primary)
                .background(status == .keep ? (isOn ? GlancePalette.accent : GlancePalette.accentSoft(scheme))
                            : GlancePalette.control(scheme), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isOn ? GlancePalette.accent : GlancePalette.border(scheme), lineWidth: isOn ? 1.5 : 0.5)
                }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(keys.0), modifiers: [])
        .background {
            // Second shortcut for the same action (letter keys).
            Button("", action: { store.rate(status, advance: autoAdvance) })
                .keyboardShortcut(KeyEquivalent(keys.1), modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        }
        .disabled(store.currentID == nil)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
