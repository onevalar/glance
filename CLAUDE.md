# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glance is a macOS image viewer application built with SwiftUI, focused on efficient image viewing and navigation with keyboard shortcuts and mouse interactions.

## Platforms

- **macOS app** (`Sources/Glance`) - the full product.
- **iPhone / iPad app** (`Sources/GlanceiOS`) - photo-library culling (PhotoKit). Shares `Models/ImageMetadata.swift` and `Shared/AppLogger.swift` with the Mac app; ratings are stored under the photo's library identifier.
- The Xcode project is **generated** from `project.yml` with XcodeGen (`xcodegen generate`); edit `project.yml`, not the `.xcodeproj`. Both apps share the bundle id `com.yourcompany.Glance` (placeholder, replace before distribution).
- iOS simulator build: `xcodebuild -scheme GlanceiOS -destination "id=<simulator udid>" -derivedDataPath build-ios build`

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
  - **ImagePreviewView.swift** - Single-image mode: loads the current image, arrow/Backspace key monitor, context menu
  - **ZoomableImageView.swift** - `GlanceImageView` (custom `NSView` that draws, zooms and pans the image) + SwiftUI bridge
  - **ImageCompareView.swift** - Multi-selection grid with synced zoom/pan
  - **CropOverlayView.swift** - Non-destructive crop frame (only stores a normalized rect)
  - **ThumbnailSidebar.swift / ImageThumbnailView.swift** - Left sidebar with rating filter, bulk "move discarded to Trash" and thumbnails
  - **ToolbarView.swift** - Bottom toolbar; the struct is named `ToolBarView` (file name differs, keep it)
  - **ImageInfoPanel.swift** - Right-hand info panel (name, pixels, size, date)
- **Models/ImageMetadata.swift** - `ImageMetadata` (rating status + crop rect) and `MetadataManager`, persisted to `~/Library/Application Support/Glance/metadata.json` keyed by file path
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
The preview and crop overlay are both sized `geometry.height + 28`; keep them identical or the crop frame drifts off the picture.

### Things to remember
- Views talk through `NotificationCenter` names `"open-image"` (reload the current image) and `"metadata-updated"`.
- Compare-mode zoom is stored relative to each picture's own fit and pan as a fraction of the zoomed picture, so photos of different sizes stay aligned.
- Tests must never use `MetadataManager.shared` (it writes the real metadata file); create `MetadataManager(saveURL:)` with a temp file.
- Supported formats: png, jpg, jpeg, gif, webp (HEIC/TIFF are not indexed).
