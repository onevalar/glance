# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glance is a macOS image viewer application built with SwiftUI, focused on efficient image viewing and navigation with keyboard shortcuts and mouse interactions.

## Platforms

- **macOS app** (`Sources/Glance`) - the full product.
- **iPhone / iPad app** (`Sources/GlanceiOS`) - photo-library culling (PhotoKit). Shares `Models/ImageMetadata.swift` and `Shared/AppLogger.swift` with the Mac app; ratings are stored under the photo's library identifier.
- The Xcode project is **generated** from `project.yml` with XcodeGen (`xcodegen generate`); edit `project.yml`, not the `.xcodeproj`. Both apps share the bundle id `com.anvalar.Glance` and are signed with team `H4982D35ZR` (automatic signing).
- **Rating model (shared, Mac + iOS)**: `ImageMetadata` = `status` (`.undecided` / `.keep` / `.discard`) + `stars` (1…5 while `.keep`). In the UI that is: **star rating 1–5** (3 or 5 selectable in settings, `starScale`), **discard** (a pile, nothing is deleted until the user confirms "清空已丢弃的照片"), or unrated. Old files that only said "keep" decode as 5 stars. `PhotoFilter` (all / unrated / stars(n) / discarded) is shared too.
- iPhone / iPad interaction (`ViewerScreen` in `RootView.swift`): the pager (`PhotoPager.swift`, a UIKit `UICollectionView`, one `PhotoCell` + `ZoomingScrollView` per photo, `PHCachingImageManager` prefetch) covers the **whole screen** under the bars. A resting photo fits inside `fitInsets` (between the top bar and the dock with 14pt air, or inside the safe area when the bars are hidden; measured in SwiftUI). Insets are re-applied in `willDisplay`, because prefetched pages are configured before the bars are measured. Zooming in lets the photo use the whole screen and hides the bars (like Photos). Scale changes made by the app (refit, cell reuse) are wrapped in `fitAdjustments` so they are never reported as a user zoom. Pulls are handed to `PullStageView` (`PullInteraction.swift`, UIKit/Core Animation): the photo is lifted onto a full-screen stage and follows the finger (grip point stays under the finger, tilt follows sideways motion). **Pull down**: it shrinks toward a **Liquid Glass bin** (`GlassBinBack` / `GlassBinFront`, SwiftUI `glassEffect` hosted in `UIHostingController`s; the photo sits between the two layers so it falls in and is seen through the glass wall). The bin rises half sunk below the bottom edge; the lid (`LidShape`, one animatable shape so the glass follows it) opens a little, then flips fully open at 150pt; release throws the photo in with its velocity, the lid shuts, the bin squashes and sinks. Glass effects on small rotated views mis-render, so rotate the shape path, not the view. **Pull up**: stars appear at the top bar's position (`StarRowView`); the photo shrinks into a glowing ball; releasing on the row picks the star under the finger, and a **throw** (≥40pt up, ≥420pt/s) picks by direction: up-left = 1 star, straight up = middle, up-right = top (±45° spread, mixing stroke and flick direction). The light streaks into the star, which bursts and fills; anything else springs back. `VerticalPanGestureRecognizer` passes nothing to the pan until the direction is known: upwards within ~50° of vertical (so throws to the side stars work), downwards within ~25°; flatter movements only page. The bars fade during a pull through `DragPhaseModel` / `ChromeFade`. Discarded photos are not dimmed anywhere.
- Top bar (3 glass controls, one job each): **album menu** `top.album` (albums with counts + 缩略图浏览 `scope.grid` → `PhotoGridView`), **position pill** `top.scope` (counter + rating filter 全部 / 未评分 / 5…1 星 / 已丢弃; tinted light red with red text in the discard pile, accent for other filters), and **更多** `top.more`: 评分方式 submenu (5 / 3 星, `starScale`), toggle 评分或丢弃后自动下一张, 操作说明. There is no settings screen. Dock `🗑 | ★★★★★ | 对比` shows the current rating (gold); for a discarded photo met while browsing, 🗑 becomes ↺ 恢复 (`dock.discard`, neutral) and the stars become a quiet "已丢弃" label. **In the discard pile** the dock is `↺ 恢复` (`dock.restore`) · `清空 N 张` (`dock.empty`, red, asks first; photos go to Recently Deleted). Same star again clears; toast offers 撤销; auto-advance on by default (restoring never advances).
- Compare (any number of photos): dock 对比 → `ComparePickerView` (in `PhotoGridView.swift`, current photo pre-selected, up to 24, 开始对比) → `CompareView`: ≤4 photos fit the screen, more scroll in a grid; zoom/pan synced through `CompareSyncHub` (late-appearing photos adopt the last state); per-photo 🗑 + stars; "同步/各自" toggle; one-time hint. `PhotoGridView` is browse-only (tap jumps to the photo). First launch shows `GestureGuide`.
- Mac keyboard: 1–5 stars (up to the chosen scale), 0 clears, X discard, R crop, ←/→; stars in the floating bar are clickable. iPad hardware keyboard: ←/→, 1–5, X / Delete, G grid, C compare.
- Liquid Glass rules (`GlanceGlass.swift`): use `glassSurface(_:)` for backgrounds (iOS 26 glass, material before that) and put glass on the plain canvas bars, not on top of the photo, so icons stay legible for full-bleed photos like screenshots. Give every glass button an explicit `.contentShape(...)` and do not use `interactive: true` on a button label — either one makes taps fall through to the photo. Text that must stay readable on any photo (compare hint) uses a solid surface instead.
- UI tests (`Tests/GlanceiOSUITests`) swipe, undo, filter, grid selection, comparison and the guide in the simulator: `xcodebuild test -scheme GlanceiOS -destination "id=<udid>" -only-testing:GlanceiOSUITests` (set `TEST_RUNNER_GLANCE_UITEST_SHOTS=<dir>` to save screenshots).
- UI tests start clean with `-resetRatings YES` (clears ratings and resets the star scale). Never commit `build-*` folders (they are in `.gitignore`).
- iOS simulator build: `xcodebuild -scheme GlanceiOS -destination "id=<simulator udid>" -derivedDataPath build-ios build`
- iOS uses the shared `GlancePalette` converted from the custom Hero UI Linear tokens, with native menus, PhotoKit permission and 44-point minimum targets. iOS ratings stay local to the device's photo identifiers and are not synced with Mac file paths.

## Build and Run

```bash
swift run                    # Build and run the app (debug, no .app bundle)
swift test                   # Run tests
xcodebuild -scheme Glance -configuration Release -derivedDataPath build -destination "platform=macOS,arch=arm64" ARCHS=arm64 ENABLE_HARDENED_RUNTIME=YES build  # Release build with .app bundle (for "Open With" testing)
```

## Project Structure

Source lives in `Sources/Glance/`:

- **GlanceApp.swift** - `@main` entry (main window "过目", settings window, "照片" menu with rating/crop shortcuts) and `AppDelegate` (file-open requests, CLI argument, folder indexing and permission prompts)
- **AppState.swift** - Global `@MainActor` state: `allImageFiles` (whole folder), `imageFiles` (after the rating filter), selection, filter, crop mode, bookmark permissions
- **ContentView.swift** - Main view: composes the layers below, owns toolbar actions, delete, rotate and the auto-hiding chrome
- **Views/**:
  - **ImagePreviewView.swift** - Single-image mode: loads the current image, arrow/Backspace key monitor, context menu; empty filters provide a return-to-all action
  - **WelcomeView.swift** - Paper-aligned startup page with a system toolbar, native importer, and the three most recent real locations. The File menu's ⌘O action also opens the importer while browsing or comparing photos.
  - **ZoomableImageView.swift** - `GlanceImageView` (custom `NSView` that draws, zooms and pans the image) + SwiftUI bridge
  - **ImageCompareView.swift** - Multi-selection grid with native synchronized zoom toggle, exit action, a focused photo and per-photo ratings. Unlinking keeps current framing; toolbar zoom/fit acts on the focused photo, and relinking adopts that photo's transform.
  - **CropOverlayView.swift** - Non-destructive editor with a native top action bar and ratio inspector. It renders the original image inside its own measured canvas; only Done writes the normalized draft to metadata. Cancel discards the draft, including Reset. Corners, edges and moving the rectangle use a fixed canvas coordinate space and gesture-start snapshot.
  - **ThumbnailSidebar.swift / ImageThumbnailView.swift** - Left sidebar with rating filter, bulk "move discarded to Trash" and thumbnails
  - **ToolbarView.swift** - Bottom toolbar; the struct is named `ToolBarView` (file name differs, keep it)
  - **ImageInfoPanel.swift** - Right-hand info panel (name, pixels, size, date)
- **Models/ImageMetadata.swift** - `ImageMetadata` (rating status + crop rect) and `MetadataManager`, persisted to `~/Library/Application Support/Glance/metadata.json` keyed by file path
- **Models/RecentLocationStore.swift** - Local-only recent history in app preferences: last-opened date, observed image count and a bookmark for an already selected resource. Deduplicates and retains six locations; the startup page shows three. Reopening still checks read access, and missing/unresolvable files require selection again. `AppState` retains the active resource's security scope across single/compare view replacement and releases it when replaced or the app terminates.
- **Models/BrowsingSessionStore.swift** - Local resource bookmark and last selected photo; startup preference defaults to the welcome page. Opting into restore reopens silently through existing read-access checks. Missing files and unavailable permissions fall back to the welcome page; Finder/CLI opens take precedence. No automatic permission prompts or expanded permissions.
- **Models/CompareSession.swift** - Relative zoom/pan, focused photo, linked and individual transforms. Keeps normalized framing across differently sized photos and resets when the compare selection changes.
- **Models/CropSession.swift** - Crop draft in normalized original-image coordinates. Resizing the window only changes its display projection, retaining the draft and aspect selection; boundary handling preserves locked ratios and the opposite corner. Geometry has no file writes.
- **Settings/** - Settings window (General / About)
- **Shared/**:
  - **AppLogger.swift** - `@AppLog` property wrapper for logging
  - **ImageRotator.swift** - In-place rotation via ImageIO (keeps format, EXIF, DPI; refuses WebP and animated GIF)
  - **ThumbnailCache.swift** - Async, cached thumbnail decoding
  - **Util.swift** - `ObjectAssociation` for ObjectiveC runtime associations
  - **Constants.swift** - App constants and identifiers
- **Permission/PermissionsManager.swift** - Handles file system permissions with bookmark data

`specs/` holds design notes (some describe plans that are not implemented, e.g. auto-update). There is no Sparkle dependency yet.

## Key Architecture Patterns

### State Management
- `AppState` (`@MainActor`) - Global app state passed via `.environmentObject()`
- `ViewState` - Per-view image transformation state, used by `ZoomableImageView`

### Naming Conventions
- **Important**: `ToolBarView` (not `ToolbarView`) - file and struct name use two-word "ToolBar"
- Enum identifiers use camelCase: `ToolbarActionIdentifier`

### Concurrency Safety
- Static properties in non-Sendable types require `nonisolated(unsafe)` annotation:
  ```swift
  enum Context {
      nonisolated(unsafe) static let hasActivated = ObjectAssociation<Bool>()
  }
  ```

### Resource Handling
- `Info.plist` and `Glance.entitlements` are NOT declared in Package.swift (SPM limitation)
- They are handled by Xcode project configuration if using Xcode

### Dependencies
- **SwiftUITooltip** - Tooltips (product: `SwiftUITooltip` from `SwiftUI-Tooltip` package)

### Logging
Use `@AppLog(category: "Name")` property wrapper:
```swift
@AppLog(category: "ViewState")
private var logger
// Usage: logger.info("message"), logger.warning("message"), logger.error("message")
```

### Image Loading Pipeline
1. User selects folder → permissions granted via bookmark data
2. `AppDelegate.loadImages()` scans directory for supported formats (png, jpg, jpeg, gif, webp)
3. Files stored in `AppState.imageFiles: [URL]`
4. `AppState.selectedImageIndex` tracks current image

### View Hierarchy (ContentView)
Layout follows the Paper file "03 · Glance 过目 · 界面与交互" (artboards 01–09). The app draws its own title bar; the system toolbar is not used (on macOS 26 it adds glass capsules that differ from the design).
```
ContentView
├── (no photos)  ImagePreviewView → WelcomeView
├── (cropping)   CropOverlayView            title bar + canvas + 260pt inspector
└── browser
    ├── GlanceTitleBar (52pt)               sidebar toggle · folder/count · search · compare · info · more menu
    ├── ThumbnailSidebar (208pt)            folder name, filter "全部 N ▾", photo cards (image, file name, rating)
    ├── canvas
    │   ├── ImagePreviewView → ZoomableImageView   (fitInsets keep the photo clear of the counter and bar)
    │   │   or ImageCompareView                    (2+ selected; own title bar, hides sidebar and info panel)
    │   ├── counter label "01 / 24  file name" (top-left)
    │   └── ToolBarView  ‹ 丢弃 X | 待定 U | 保留 P › 裁剪 R   (floating, auto-hides after 5s)
    └── ImageInfoPanel (260pt)              文件名 / 尺寸 / 格式 / 所在位置 / 标记
```
- `GlanceTitleBar` + `TrafficLightInset` (Views/GlanceTitleBar.swift) centre the system traffic lights in the 52pt bar; every screen (welcome, browser, compare, crop) uses the same bar.
- Colours come from `GlancePalette` (sRGB conversions of the design tokens): `surface`, `inspector`, `canvas`, `foreground/secondary/muted`, `divider`, `fieldBorder`, `buttonFill`, `accent`.
- The UI is Chinese only (design language); the string catalog has no English entries and the app declares `zh-Hans`.
- Rating wording: 丢弃 / 待定 / 保留 (`ImageStatus.title`).
- Visual check without a display: `GLANCE_SNAPSHOT_DIR=<folder of photos> GLANCE_SNAPSHOT_MODE=browse|compare|crop|welcome [GLANCE_SNAPSHOT_DARK=0] swift test --filter SnapshotTests` writes `snapshot-<mode>-<scheme>.png` next to the photos. Compare it with the Paper artboards (read via the Paper MCP).

### Things to remember
- Views talk through `NotificationCenter` names `"open-image"` (reload the current image) and `"metadata-updated"`.
- Compare-mode zoom is stored relative to each picture's own fit and pan as a fraction of the zoomed picture, so photos of different sizes stay aligned.
- Tests must never use `MetadataManager.shared` (it writes the real metadata file); create `MetadataManager(saveURL:)` with a temp file.
- The window is sandboxed: the first time a folder is opened the system asks for access to it.
- Supported formats: png, jpg, jpeg, gif, webp (HEIC/TIFF are not indexed).
