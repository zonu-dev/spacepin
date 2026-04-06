# SpacePin

SpacePin is a minimal native macOS menu bar app that shows note pins and image pins in small floating windows. Each pin uses the app's own `NSPanel` window, not the system Picture in Picture API and not another app's window.

## What It Does

- Creates note pins that can be edited in place
- Lets note pins switch between built-in color presets
- Lets note pins change their body font size from the manager window
- Uses `Untitled` as the default note title and allows header titles to be edited in place
- Creates image pins from file selection or drag and drop
- Keeps multiple pins open at the same time
- Lets each pin collapse down to its header and expand again from the pin header
- Uses floating `NSPanel` windows configured with `canJoinAllSpaces` and `fullScreenAuxiliary`
- Restores pin kind, frame, opacity, lock state, click-through state, note text, and stored image file on relaunch
- Provides a menu bar control surface plus a lightweight manager window for richer pin controls

## Implementation Notes

- Language: Swift
- UI: SwiftUI for the manager window, AppKit for the floating pin window contents
- Floating windows: AppKit `NSPanel`
- App shell: AppKit `NSStatusItem` with accessory activation policy
- Xcode app target: generated macOS app project with sandbox entitlements and asset catalog
- Persistence: JSON in `~/Library/Application Support/SpacePin/pins.json`
- Imported images: copied into `~/Library/Application Support/SpacePin/images/`

## Build And Run

Requirements:

- macOS 13 or later
- Xcode 26.4 or later

From Terminal:

```bash
swift build --disable-sandbox
swift run --disable-sandbox SpacePin
```

Generate the Xcode project and build a `.app` bundle:

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild \
  -project SpacePin.xcodeproj \
  -scheme SpacePin \
  -derivedDataPath .derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The unsigned app bundle is then available at `.derived/Build/Products/Debug/SpacePin.app`.

To archive for App Store distribution:

```bash
scripts/archive_app_store.sh
```

To export a signed archive after archiving:

```bash
scripts/export_app_store.sh
```

To build a signed DMG for direct distribution:

```bash
scripts/build_release_dmg.sh
```

The direct-download DMG is then available at `.derived/SpacePin.dmg`.

To notarize the direct-download app and DMG:

```bash
xcrun notarytool store-credentials spacepin-notary \
  --apple-id 'you@example.com' \
  --team-id 'TEAMID1234' \
  --password '<app-specific-password>'

SPACEPIN_NOTARY_KEYCHAIN_PROFILE=spacepin-notary \
scripts/notarize_release_dmg.sh
```

To upload the notarized DMG over an existing GitHub release asset in one step:

```bash
SPACEPIN_NOTARY_KEYCHAIN_PROFILE=spacepin-notary \
SPACEPIN_GITHUB_RELEASE_TAG=v1.0.3 \
scripts/notarize_release_dmg.sh
```

From Xcode:

1. Open `SpacePin.xcodeproj` (or run `xed SpacePin.xcodeproj`).
2. Confirm the Team and bundle identifier in Signing & Capabilities.
3. Select the `SpacePin` scheme and archive or run the app.

## Current Behavior

- The app runs as a menu bar utility and hides its Dock icon.
- The menu bar menu can create pins, import images, open the manager window, bring all pins forward, and manage individual pins.
- Note pins and image pins open as borderless floating panels.
- Pins can be moved by dragging the panel background or header area.
- Pins can be resized from the panel edges.
- The manager window can change note color presets, note body font size, lock a pin, enable click-through, change opacity, duplicate, delete, and bring a pin to the front.
- Each pin header includes inline title editing, collapse or expand, lock toggle, duplicate, delete, and note color selection for notes.
- Closing a pin window deletes that pin.

## Space Behavior And Limits

SpacePin uses only public AppKit APIs:

- `NSPanel`
- `NSWindow.Level.floating`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`

What this can do:

- Keep the pin windows visible while switching between normal desktop Spaces
- Request that the windows participate as auxiliary floating windows around full-screen contexts

What macOS does not publicly guarantee:

- Third-party overlay windows are not guaranteed to appear above every full-screen app in every situation.
- Behavior can vary by macOS version, Mission Control state, Stage Manager, and the active full-screen app.
- This app does not use private APIs or force itself into the system PiP slot.

In practice, this implementation makes the strongest public API request that is reasonable for a PiP-like utility window, but full-screen overlay behavior still has OS-level limits.

## Known Limitations

- Click-through pins must be disabled from the manager window because the pin itself stops receiving mouse events.
- Imported images are copied into Application Support instead of live-linking to the original file.
- There is no per-pin toolbar for changing opacity or lock state directly inside the pin window.
- Full-screen overlay behavior has OS-level limits depending on macOS version and Mission Control state.

## Tests

The included tests cover:

- Pin record duplication and title behavior
- JSON persistence round-trip for pins
- Imported image asset copy and cleanup behavior

Run:

```bash
swift test --disable-sandbox
```

For the Xcode app target:

- `xcodebuild -project SpacePin.xcodeproj -scheme SpacePin -derivedDataPath .derived CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project SpacePin.xcodeproj -scheme SpacePin -derivedDataPath .derived -destination 'generic/platform=macOS' -archivePath .derived/SpacePin.xcarchive CODE_SIGNING_ALLOWED=NO archive`
- `xcodebuild -project SpacePin.xcodeproj -scheme SpacePinTests -derivedDataPath .derived CODE_SIGNING_ALLOWED=NO test`

In this environment, the `SpacePinTests` scheme builds but the test runner still fails to launch because of a local PTY or execution permission restriction. The SwiftPM test suite above passes.

## App Store Readiness

Included in this repository:

- Sandboxed macOS app target with `com.apple.security.app-sandbox`
- Read-only user-selected file access entitlement for image import via open panel
- App category set to `public.app-category.productivity`
- App icon in `.icon` format with ICNS fallback
- Archive and export helper scripts for App Store packaging

See [docs/app-store-submission.md](docs/app-store-submission.md) for the submission checklist.

## Possible Next Extensions

- Add a global quick-add shortcut
- Support drag-and-drop directly onto existing image pins to replace content
- Add snap positions, pin presets, and richer note styling
