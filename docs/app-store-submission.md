# SpacePin App Store Submission Checklist

## Fixed Project Values

- App name: `SpacePin`
- Bundle ID: `com.zoochigames.spacepin`
- Team ID: set in `scripts/generate_xcodeproj.rb`
- Category: `Productivity`
- Minimum macOS version: `13.0`

## Local Release Steps

1. Regenerate the Xcode project if needed.

```bash
ruby scripts/generate_xcodeproj.rb
```

2. Build the app locally.

```bash
xcodebuild \
  -project SpacePin.xcodeproj \
  -scheme SpacePin \
  -derivedDataPath .derived \
  build
```

3. Run the SwiftPM tests.

```bash
swift test --disable-sandbox
```

4. Archive a signed build.

```bash
scripts/archive_app_store.sh
```

5. Export the archive if needed.

```bash
scripts/export_app_store.sh
```

Both scripts complete successfully with valid signing certificates installed.

## Manual QA Before Submission

- Launches from the menu bar with no Dock icon
- `New Note Pin` works
- `Import Image…` works
- Multiple pins stay open
- Pins move and resize correctly
- Note title editing works
- Note color and font size controls work
- Lock and click-through controls work
- Pin collapse and restore works
- State restores after quitting and relaunching
- Pins appear across normal Spaces
- Behavior on full-screen Spaces is acceptable and matches README limitations

## App Store Connect

Create or confirm the app record with:

- Name: `SpacePin`
- Bundle ID: `com.zoochigames.spacepin`
- SKU: choose a stable internal value such as `spacepin-mac-001`

Then fill in:

- Subtitle
- Description
- Keywords
- Support URL
- Privacy Policy URL
- Marketing URL if desired
- Copyright
- Pricing and Availability
- Age Rating
- App Privacy answers
- App Review contact information

## Screenshots

Use the prepared macOS screenshots in this order. Japanese screenshots are in
`docs/screenshots/`; English screenshots are in `docs/screenshots/en/`.

1. `docs/screenshots/spacepin-1.png` — Quick palette entry point
2. `docs/screenshots/spacepin-2.png` — Text and image memos near the workspace
3. `docs/screenshots/spacepin-3.png` — Memos pinned above a full-screen app
4. `docs/screenshots/spacepin-4.png` — Bring all memos forward across desktops
5. `docs/screenshots/spacepin-5.png` — Open and stored memo state indicators

## Review Notes Draft

Use a short note similar to this:

> SpacePin is a menu bar utility for macOS. The app does not present a Dock icon during normal use. Open it from the menu bar icon, then use `New Note Pin` or `Import Image…` to create floating pins. The floating windows are implemented with public AppKit `NSPanel` APIs.

Updated version:

> SpacePin is a menu bar utility for macOS. The app does not present a Dock icon during normal use. Open it from the menu bar icon or press Shift + Command + Space, then use `New Text Memo` or `New Image Memo` to create floating memos. The floating windows are implemented with public AppKit `NSPanel` APIs.

## Remaining Non-Code Inputs

- Public Privacy Policy URL on `zoochigames.com`
- Final screenshots in `docs/screenshots/spacepin-1.png` through `docs/screenshots/spacepin-5.png`
- App Store Connect copy from `docs/app-store-metadata-localizations.json`
