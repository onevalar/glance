//
//  GeneralSettingsPane.swift
//  Glance
//
//  Created by 李旭 on 2024/9/12.
//

import SwiftUI

struct GeneralSettingsPane: View {
    @AppLog(category: "View-GeneralSettingsPane")
    private var logger

    @EnvironmentObject var appState: AppState

    @State private var showDirImporter = false

    @AppStorage("showCurDirImg")
    private var showCurDirImg = true
    @AppStorage("glance.appearance") private var appearance = GlanceAppearance.system.rawValue
    @AppStorage("glance.autoHideControls") private var autoHideControls = true
    @AppStorage("glance.startup") private var startup = GlanceStartup.welcome.rawValue

    private var permissionDirs: [PermissionDir] {
        appState.dirs.map { PermissionDir(url: $0) }
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("界面外观", selection: $appearance) {
                    ForEach(GlanceAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("图片画布、缩略图、工具栏和信息面板会一起切换。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("专注浏览") {
                Picker("启动时", selection: $startup) {
                    Text("显示启动页").tag(GlanceStartup.welcome.rawValue)
                    Text("恢复上次浏览").tag(GlanceStartup.resume.rawValue)
                }
                Text("恢复已打开的位置和最后选中的照片。文件移动或无法读取时显示启动页。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("闲置时自动隐藏工具栏", isOn: $autoHideControls)
                Text("移动到窗口底部可唤回工具栏；点击照片可随时显示或隐藏。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            imageBrowsingSection
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Section 1: 图片浏览

    @ViewBuilder
    private var imageBrowsingSection: some View {
        Section {
            Toggle(isOn: $showCurDirImg) {
                Text("自动索引文件夹中的图片")
                Text("打开图片时自动加载同一文件夹下的所有图片")
            }

            if showCurDirImg {
                HStack {
                    Spacer()
                    Button(action: {
                        showDirImporter = true
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding([.leading, .trailing], 16)

                if permissionDirs.isEmpty {
                    Text("点击 + 添加授权文件夹，添加后打开该文件夹内的图片无需再次授权。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding([.leading, .trailing], 16)
                } else {
                    List {
                        ForEach(Array(permissionDirs.enumerated()), id: \.element.path) { index, dir in
                            HStack {
                                Text(dir.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(2)
                                Spacer()
                                Button(action: {
                                    appState.dirs.remove(at: index)
                                    appState.storeBookmarkData()
                                }) {
                                    Image(systemName: "delete.left")
                                }
                                .accessibilityLabel(Text("移除授权文件夹"))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showDirImporter,
            allowedContentTypes: [.directory],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let dirs):
                if let dir = dirs.first {
                    let gotAccess = dir.startAccessingSecurityScopedResource()
                    if gotAccess {
                        if !appState.dirs.contains(dir) {
                            appState.dirs.append(dir)
                            appState.storeBookmarkData()
                        }
                    } else {
                        logger.warning("Failed to access directory: \(dir.path)")
                    }
                }
            case .failure(let error):
                logger.error("File importer failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    GeneralSettingsPane()
}
