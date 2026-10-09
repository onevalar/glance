//
//  GlanceGlass.swift
//  Glance (iPhone / iPad)
//

import SwiftUI

extension View {
    /// Floating-control background: Liquid Glass on iOS 26, a blurred material before that.
    /// Every control that sits on top of a photo uses this so it stays readable on any picture.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay { if let tint { shape.fill(tint.opacity(0.35)) } }
        }
    }

    @available(iOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Groups neighbouring glass shapes so they blend and animate together (iOS 26); a plain container before.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
