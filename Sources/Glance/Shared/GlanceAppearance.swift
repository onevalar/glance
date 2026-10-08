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
}
