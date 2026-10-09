#if os(macOS)
import AppKit
#endif
import SwiftUI

enum GlanceAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
    var title: LocalizedStringKey {
        switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" }
    }
}

/// sRGB conversions of the user's Hero UI Linear tokens, shared by SwiftUI and AppKit.
enum GlancePalette {
    static let accent = Color(red: 0.149, green: 0.392, blue: 0.780)
    #if os(macOS)
    static func canvasColor(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0.031352, green: 0.035341, blue: 0.039341, alpha: 1)
             : NSColor(srgbRed: 0.957658, green: 0.960922, blue: 0.966188, alpha: 1)
    }
    /// Card/sidebar surface (matches `surface(_:)`), for AppKit drawing.
    static func surfaceColor(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 15 / 255, green: 16 / 255, blue: 16 / 255, alpha: 1) : .white
    }
    #endif
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.031352, green: 0.035341, blue: 0.039341)
                        : Color(red: 0.957658, green: 0.960922, blue: 0.966188)
    }
    static func accentSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 26 / 255, green: 33 / 255, blue: 45 / 255)
                        : Color(red: 221 / 255, green: 228 / 255, blue: 240 / 255)
    }
    static func control(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 29 / 255, green: 29 / 255, blue: 30 / 255) : raised(scheme)
    }
    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.027735, green: 0.027735, blue: 0.027735)
                        : Color(red: 0.905295, green: 0.911757, blue: 0.922179)
    }
    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.058245, green: 0.063059, blue: 0.063061) : .white
    }
    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.121370, green: 0.125219, blue: 0.132921)
                        : Color(red: 0.854771, green: 0.864360, blue: 0.879827)
    }

    // MARK: - Paper design tokens (sRGB conversions of the Hero UI Linear theme)

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
    static func foreground(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0xE3E3E6) : hex(0x181B20) }
    static func secondary(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0xD0D6E0) : hex(0x292D33) }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0x8A8F98) : hex(0x50545B) }
    static func fieldBorder(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0x23252A) : hex(0xC0C4CB) }
    static func divider(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0x1F2022) : hex(0xE7E8EC) }
    /// Button fill inside the floating bar (light: #EDF0F4, dark: same as the bar).
    static func buttonFill(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0x1D1D1E) : hex(0xEDF0F4) }
    /// Title bar and sidebar surface.
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0x0F1010) : .white }
    /// Right-hand information panel.
    static func inspector(_ scheme: ColorScheme) -> Color { scheme == .dark ? hex(0x070707) : .white }
}
