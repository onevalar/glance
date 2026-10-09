# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glance is a macOS image viewer application built with SwiftUI, focused on efficient image viewing and navigation with keyboard shortcuts and mouse interactions.

## Platforms

- **macOS app** (`Sources/Glance`) - the full product.
- **iPhone / iPad app** (`Sources/GlanceiOS`) - photo-library culling (PhotoKit). Shares `Models/ImageMetadata.swift` and `Shared/AppLogger.swift` with the Mac app; ratings are stored under the photo's library identifier.
- The Xcode project is **generated** from `project.yml` with XcodeGen (`xcodegen generate`); edit `project.yml`, not the `.xcodeproj`. Both apps share the bundle id `com.anvalar.Glance` and are signed with team `H4982D35ZR` (automatic signing).
- iPhone / iPad interaction (one immersive screen; controls are Liquid Glass floating over the photo): the photo fills the display; **swipe up = keep, swipe down = discard** (rubber-band drag in `ZoomingScrollView`, HUD while dragging, release past ~80pt commits), left/right turns the page, double-tap or pinch zooms. The same actions are always visible in the **bottom glass dock** `丢弃 | 待定 | 保留 | 对比`. Choosing the status a photo already has clears it back to 待定; a toast offers 撤销 for 3.5s; the current photo's rating shows as a badge; auto-advance after rating is on by default.
- Top (glass): album menu "全部照片 ▾", counter, grid button, "…" menu; below it the filter capsule `全部 / 保留 / 待定 / 丢弃` with counts. A single tap on the photo hides all controls.
- Compare: tap 对比 in the dock → `PhotoGridView(pickForCompare:)` opens with the current photo already selected, tap 1–3 more, press the big 开始对比 button → `CompareView` (zoom/pan synced through `CompareSyncHub`, per-photo 丢弃/保留 chips, "同步/各自" toggle, one-time hint). The browse grid (grid button) has "选择"/long-press for the same thing. First launch shows `GestureGuide`.
- Liquid Glass rules (`GlanceGlass.swift`): use `glassSurface(_:)` for backgrounds (iOS 26 glass, material before that). Give every glass button an explicit `.contentShape(...)` and do not use `interactive: true` on a button label — either one makes taps fall through to the photo. Text that must stay readable on any photo (compare hint) uses a solid surface instead.
- iPad uses the same screen; hardware keyboard: ←/→, 1/2/3, X/U/P, G for the grid. The Mac app keeps its keyboard shortcuts (1/2/3, X/U/P, R, arrows).
- UI tests (`Tests/GlanceiOSUITests`) swipe, undo, filter, grid selection, comparison and the guide in the simulator: `xcodebuild test -scheme GlanceiOS -destination "id=<udid>" -only-testing:GlanceiOSUITests` (set `TEST_RUNNER_GLANCE_UITEST_SHOTS=<dir>` to save screenshots).
- Never commit `build-*` folders (they are in `.gitignore`).
- iOS simulator build: `xcodebuild -scheme GlanceiOS -destination "id=<simulator udid>" -derivedDataPath build-ios build`
- iOS uses the shared `GlancePalette` converted from the custom Hero UI Linear tokens, with native menus, PhotoKit permission and 44-point minimum toolbar targets. Rating controls use neutral surfaces and one blue accent; thumbnails are accessible buttons. Photos fit between the controls, and the filmstrip hides at compact height so landscape photos remain unobscured. Zoom stays clipped to its viewport. Reduced Motion disables sidebar, chrome, filmstrip and double-tap zoom animations; Reduced Transparency replaces the bottom material with a solid canvas. iOS ratings stay local to the device's photo identifiers and are not synced with Mac file paths.

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
