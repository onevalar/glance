//
//  SettingsWindow.swift
//  Glance
//
//  Created by 李旭 on 2024/9/11.
//

import SwiftUI

struct SettingsWindow: Scene {
    @AppStorage("glance.appearance") private var appearance = GlanceAppearance.system.rawValue
    @ObservedObject var appState: AppState
    let onAppear: () -> Void

    var body: some Scene {
        Window("Settings", id: Constants.settingsWindowID) {
            SettingsView()
                .preferredColorScheme(GlanceAppearance(rawValue: appearance)?.scheme)
                .tint(GlancePalette.accent)
                .frame(minWidth: 825, minHeight: 500)
                .onAppear(perform: onAppear)
                .environmentObject(appState)
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 615)
    }
}
