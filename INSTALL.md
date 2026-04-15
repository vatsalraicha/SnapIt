# SnapIt - Installation Guide

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode (with command line tools) for building from source
- Apple Silicon or Intel Mac

## Build & Install from Source

```bash
cd SnapIt
xcodebuild -project SnapIt.xcodeproj -scheme SnapIt -configuration Release -derivedDataPath build clean build
cp -R build/Build/Products/Release/SnapIt.app /Applications/
```

## First Launch

1. Open **SnapIt** from `/Applications` or Spotlight
2. If macOS blocks the app, go to **System Settings > Privacy & Security** and click **Open Anyway**
3. Grant the following permissions when prompted:
   - **Screen Recording** - required for all captures
   - **Accessibility** - required for scrolling capture and global hotkeys

## Permissions

You can manage permissions at any time in:
**System Settings > Privacy & Security**

| Permission    | Required For                          |
|---------------|---------------------------------------|
| Screen Recording | All screenshot captures            |
| Accessibility    | Scrolling capture, global hotkeys  |

## Versioning

The app version is defined in two places:

- **`Resources/Info.plist`** - `CFBundleShortVersionString` (display version, e.g. `1.0.0`)
- **`SnapIt.xcodeproj/project.pbxproj`** - `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`

To bump the version, update both `MARKETING_VERSION` in the Xcode project (or project.pbxproj) and `CFBundleShortVersionString` in Info.plist.

The About dialog (menu bar > About SnapIt) reads the version dynamically from the app bundle.

## Updating

To update an existing installation:

```bash
cd SnapIt
git pull  # if using git
xcodebuild -project SnapIt.xcodeproj -scheme SnapIt -configuration Release -derivedDataPath build clean build
cp -R build/Build/Products/Release/SnapIt.app /Applications/
```

Quit SnapIt before replacing the app, or macOS may block the copy.
