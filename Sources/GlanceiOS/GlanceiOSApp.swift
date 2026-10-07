//
//  GlanceiOSApp.swift
//  Glance (iPhone / iPad)
//

import SwiftUI

@main
struct GlanceiOSApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
