# SpacePin App Store Metadata Draft

Localized variants for the current runtime locale set are available in [app-store-metadata-localizations.json](app-store-metadata-localizations.json).

## App Name

`SpacePin`

## Subtitle Candidates

- Pin notes and images across Spaces
- Floating notes and images for Mac
- Keep notes and images always nearby

## Keywords

`notes,pin,sticky,image,floating,desktop,spaces,overlay,reference,productivity`

## Short Description Draft

SpacePin lets you pin notes and images in small floating windows that stay available across macOS Spaces. Keep reference material, reminders, and visual snippets nearby without switching back and forth between apps.

## Full Description Draft

SpacePin is a lightweight macOS menu bar utility for keeping important notes and images visible while you work.

Create note pins for quick text reminders, or import images as visual reference pins. Each pin opens in a compact floating window that you can move, resize, lock, collapse, duplicate, and keep across Spaces.

SpacePin is designed for workflows where you need information to stay close at hand:

- Keep checklists and reminders visible
- Pin image references while designing or writing
- Place multiple notes and images around your workspace
- Adjust opacity and click-through behavior to fit your setup
- Restore your pins after relaunch

Key features:

- Create editable note pins
- Import image pins from files
- Show multiple pins at once
- Move and resize each pin freely
- Keep pins visible across macOS Spaces
- Lock, collapse, duplicate, and remove pins
- Restore note text, image references, size, and position after restart

SpacePin uses native macOS windowing with public system APIs and is built to feel lightweight and unobtrusive.

## Privacy Position

Suggested App Privacy answer if the shipping build stays as-is:

- Data Not Collected

Rationale:

- No account system
- No analytics
- No ads
- No remote sync
- Imported files stay local on the Mac

Re-check this before submission if any telemetry, crash reporting, sync, or web services are added.

## Review Notes Draft

SpacePin is a menu bar utility for macOS.

How to review:

1. Launch the app.
2. Click the menu bar icon for SpacePin.
3. Use `New Note Pin` to create a note, or `Import Image…` to create an image pin.
4. Use `Open Manager` for additional controls such as opacity, lock, color, and font size.

Notes:

- The app normally runs without a Dock icon.
- The floating windows are implemented with public AppKit `NSPanel` APIs.
- The app stores note and image pin state locally on the device.
