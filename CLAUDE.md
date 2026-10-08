# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glance is a macOS image viewer application built with SwiftUI, focused on efficient image viewing and navigation with keyboard shortcuts and mouse interactions.

## Platforms

- **macOS app** (`Sources/Glance`) - the full product.
- **iPhone / iPad app** (`Sources/GlanceiOS`) - photo-library culling (PhotoKit). Shares `Models/ImageMetadata.swift` and `Shared/AppLogger.swift` with the Mac app; ratings are stored under the photo's library identifier.
- The Xcode project is **generated** from `project.yml` with XcodeGen (`xcodegen generate`); edit `project.yml`, not the `.xcodeproj`. Both apps share the bundle id `com.anvalar.Glance` and are signed with team `H4982D35ZR` (automatic signing).
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
```
ContentView (GeometryReader + ZStack)
├── ThumbnailSidebar (left, hidden with the toolbar button; only when > 1 image)
├── ImageInfoPanel (right, optional)
├── ImagePreviewView → ZoomableImageView   (single selection)
│   or ImageCompareView                    (2+ selected images)
├── left / right navigation arrows
├── ToolBarView (bottom, floating, auto-hides after 5s)
└── CropOverlayView (only while cropping)
```
The browsing preview includes the hidden-title-bar height (`geometry.height + 28`). The crop editor has its own image canvas below the action bar and beside the inspector; both its image and handles use that canvas's measured size. Do not project crop handles using the whole window size.

### Things to remember
- Views talk through `NotificationCenter` names `"open-image"` (reload the current image) and `"metadata-updated"`.
- Compare-mode zoom is stored relative to each picture's own fit and pan as a fraction of the zoomed picture, so photos of different sizes stay aligned.
- Tests must never use `MetadataManager.shared` (it writes the real metadata file); create `MetadataManager(saveURL:)` with a temp file.
- Supported formats: png, jpg, jpeg, gif, webp (HEIC/TIFF are not indexed).
