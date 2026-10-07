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

    private var current: ImageStatus? {
        store.currentID.map { metadata.getMetadata(forKey: $0).status }
    }

    var body: some View {
        HStack(spacing: 10) {
            button(.discard, title: "丢弃", icon: "xmark", tint: .red, keys: ("1", "x"))
            button(.undecided, title: "不确定", icon: "questionmark", tint: .orange, keys: ("2", "u"))
            button(.keep, title: "保留", icon: "flag.fill", tint: .green, keys: ("3", "p"))
        }
    }

    private func button(
        _ status: ImageStatus,
        title: String,
        icon: String,
        tint: Color,
        keys: (Character, Character)
    ) -> some View {
        let isOn = current == status
        return Button {
            store.rate(status, advance: autoAdvance)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(isOn ? Color.white : tint)
                .background(isOn ? tint : tint.opacity(0.15), in: .rect(cornerRadius: 12))
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
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
