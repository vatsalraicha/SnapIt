# SnapIt

A native macOS screenshot tool built in Swift. Captures, annotates, and exports screenshots — all from the menu bar.

## Why

macOS built-in screenshot is limited: no annotation, no scrolling capture, no OCR. Third-party tools like Shottr exist but aren't open-source. SnapIt fills the gap — a fast, lightweight, zero-dependency screenshot app optimized for Apple Silicon.

## What It Does

### Capture Modes

| Mode | Shortcut | Description |
|------|----------|-------------|
| **Area** | ⌃⇧4 | Draw a rectangle to capture any region |
| **Fullscreen** | ⌃⇧3 | Capture the entire screen under the cursor |
| **Window** | ⌃⇧W | Click any window to capture it (auto-trims shadow) |
| **Scrolling** | ⌃⇧S | Select an area, then auto-scrolls and stitches a full-page capture |
| **OCR** | ⌃⇧T | Select text on screen, copies it to clipboard |
| **Scrolling + OCR** | Menu only | Scrolling capture followed by text extraction |
| **Repeat Last** | ⌃⇧R | Re-captures the same area as your last capture |
| **Delayed** | Menu only | 3s or 5s countdown, then area capture |

All shortcuts are customizable in Preferences → Hotkeys.

### Editor

After capture, screenshots are auto-saved and/or copied to clipboard (configurable). Open the editor from the menu bar to annotate.

**13 annotation tools:**
- **Arrow & Line** — Straight lines with optional arrowheads
- **Rectangle & Oval** — Outline or filled shapes
- **Text** — Inline editable text with font/color control
- **Freehand & Highlighter** — Pen drawing and semi-transparent highlighting
- **Spotlight** — Darkens everything except a selected region
- **Step Counter** — Numbered circles (1, 2, 3...) for step-by-step guides
- **Pixelate** — Blur/scramble a region to redact sensitive info
- **Ruler** — Measure pixel distances
- **Color Picker** — Eyedropper that copies color in Hex, RGB, HSL, or OKLCH
- **Crop** — Interactive crop with confirm (Return) / cancel (Escape)

**Editor shortcuts:**
- ⌘C Copy | ⌘S Save | ⌘P Print | ⌘Z Undo | ⌘⇧Z Redo
- ⌘0 Reset zoom | ⌘1 Fit to window
- Arrow keys to nudge annotations | Delete to remove

### OCR & QR Detection

- Select any region → text is recognized and copied to clipboard
- Multi-language support (English, Chinese, Japanese, Korean, French, German, Spanish, and more)
- Preserves multi-column layout structure
- Automatically detects QR codes and barcodes in screenshots

### Smart File Naming

Screenshots are named with the window title when possible:
```
SnapIt_Safari - GitHub_2026-04-14_21.30.45.png
```
Falls back to `SnapIt_timestamp.png` when no window is detected.

### Export

- **Auto-copy to clipboard** after every capture (default on)
- **Auto-save** to a configured folder
- **Manual save** via ⌘S with format picker (PNG, JPEG, TIFF)
- **Auto-format detection** — PNG for UI/text screenshots, JPEG for photos
- **Pin** — Float the screenshot as an always-on-top window
- **S3 upload** — Infrastructure ready (AWS Signature V4)

## Architecture

```
Menu Bar (StatusBarController)
    │
    ├── Global Hotkeys (Carbon Event API)
    │
    └── CaptureManager (singleton)
            │
            ├── AreaCaptureOverlay ──────┐
            ├── WindowCaptureOverlay ────┤
            ├── ScrollCaptureEngine ─────┤
            │   (Vision framework        │
            │    for stitching)          │
            └── Fullscreen/OCR ─────────┤
                                        ▼
                                  openEditor()
                                   │       │
                             auto-save  auto-copy
                                   │
                               showEditor()
                                   │
                             EditorWindow
                                   │
                          EditorViewController
                                   │
                              CanvasView
                           (image + annotations)
```

### Key Components

| Component | File(s) | Role |
|-----------|---------|------|
| App lifecycle | `AppDelegate.swift`, `main.swift` | Launch, menu bar setup, hotkey registration |
| Menu bar | `StatusBarController.swift` | Menu items, action routing |
| Capture | `ScreenCapture.swift` | Central coordinator for all capture modes |
| Area selection | `AreaCaptureOverlay.swift` | Full-screen overlay, rectangle drawing |
| Window selection | `WindowCapture.swift` | Window highlight, click-to-capture |
| Scroll capture | `ScrollCapture.swift` | Auto-scroll, Vision stitching |
| Editor | `EditorWindow.swift`, `EditorViewController.swift` | Window management, toolbar, tool switching |
| Canvas | `CanvasView.swift` | Image rendering, annotations, input handling |
| OCR | `TextRecognizer.swift`, `LayoutAnalyzer.swift` | Text recognition, layout preservation |
| QR | `QRDetector.swift` | Barcode/QR detection |
| Export | `FileExporter.swift`, `ClipboardManager.swift` | Save, copy, format detection |
| Hotkeys | `GlobalHotkey.swift` | Carbon API registration, system-wide shortcuts |
| Settings | `PreferencesManager.swift`, `PreferencesView.swift` | UserDefaults storage, SwiftUI preferences UI |
| Image utils | `ImageProcessing.swift` | Resize, crop, shadows, gradients, GIF creation |

## Technical Decisions

### Why ScreenCaptureKit (not CGDisplayCreateImage)
Modern Apple framework, optimized for Apple Silicon, supports per-window capture with automatic shadow handling. Requires macOS 13+.

### Why full-display-then-crop
ScreenCaptureKit's `sourceRect` has coordinate/mirroring bugs on multi-display setups. Capturing the full display and cropping in code is more reliable.

### Why Vision framework for scroll stitching
`VNTranslationalImageRegistrationRequest` computes the exact pixel offset between two overlapping images. More accurate than row-hash comparison or naive overlap detection — handles sub-pixel rendering, anti-aliasing, and repeated patterns.

### Why Carbon for global hotkeys
No external dependencies. The Carbon Event Manager API is the only way to register truly global keyboard shortcuts on macOS without accessibility event taps. Requires Accessibility permission.

### Why CGEvent for scroll posting
NSEvent only works within the app's own context. CGEvent posts scroll events to any focused window. Momentum scrolling is explicitly disabled by zeroing the scroll phase fields.

### Why menu bar app
Screenshots should be instant. A dock app requires switching contexts. A menu bar app is always accessible, and the dock icon only appears when the editor is open (managed via `setActivationPolicy`).

## Permissions

| Permission | Required For | Prompted When |
|------------|-------------|---------------|
| **Screen Recording** | All capture modes (ScreenCaptureKit) | First capture attempt |
| **Accessibility** | Global hotkeys, scrolling capture | First hotkey press / scroll capture |

Grant in: **System Settings → Privacy & Security**

## Preferences

| Tab | Settings |
|-----|----------|
| **General** | Launch at login, save folder, auto-save, auto-copy, Esc behavior |
| **Hotkeys** | Customizable shortcuts for all 6 capture modes |
| **Appearance** | Window shadow mode, fit-to-window zoom, annotation color |
| **Advanced** | OCR languages, color format, physical pixels, strip line breaks |
| **Upload** | S3 endpoint, bucket, access key, secret key, region |

## Frameworks

All Apple-native, zero third-party dependencies:

- **Cocoa** — UI, windows, views
- **ScreenCaptureKit** — Screen/window capture
- **Vision** — OCR, image registration, barcode detection
- **CoreImage** — Image filters, color analysis
- **QuartzCore** — Layer rendering
- **Carbon** — Global hotkey registration

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel
- Xcode (for building from source)

## Install

```bash
cd SnapIt
xcodebuild -project SnapIt.xcodeproj -scheme SnapIt -configuration Release -derivedDataPath build clean build
cp -R build/Build/Products/Release/SnapIt.app /Applications/
```

See [INSTALL.md](INSTALL.md) for detailed instructions including permissions setup and versioning.
