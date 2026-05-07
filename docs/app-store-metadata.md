# SpacePin App Store Metadata Draft

Localized variants for the current runtime locale set are available in [app-store-metadata-localizations.json](app-store-metadata-localizations.json).

## App Name

`SpacePin`

## Subtitle Candidates

- Memo palette for your Mac
- Quick memos across Spaces
- Text and image memos nearby

## Keywords

`memo,notes,image,sticky,floating,desktop,spaces,overlay,palette,reference`

## Short Description Draft

SpacePin opens a quick palette for keeping text and image memos close while you work across macOS Spaces.

## Full Description Draft

SpacePin is a lightweight menu bar app for keeping text and image memos close while you work.

Open the quick palette with Shift + Command + Space, create text or image memos, and bring stored memos back to the front from a 10x4 inventory-style palette. Memos open as compact floating panels that you can move, resize, collapse into the palette, and restore after relaunch.

SpacePin is designed for workflows where small pieces of information need to stay close at hand:

- Keep checklists and reminders visible
- Keep image references beside your current app
- Store and recall memos from the quick palette
- Bring all memos to the front across Spaces
- Restore memo text, images, position, and size after relaunch

Key features:

- Create text memos
- Create image memos from files
- Open the quick palette with a customizable shortcut
- Arrange memo icons in a 10x4 palette
- Show whether each memo is open or stored
- Move and resize each memo freely
- Collapse memos back into the palette
- Bring all memos to the front

SpacePin uses native macOS windowing with public system APIs and is built to feel lightweight and unobtrusive.

## What's New Draft

Redesigned the quick palette as a 10x4 memo inventory.
Added open and stored state indicators for memo icons.
Added drag-and-drop ordering for palette memo icons.
Refined text and image memo window controls.
Improved image memo initial sizing and quick palette shortcut settings.

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
3. Use `New Text Memo` to create a text memo, or `New Image Memo` to create an image memo.
4. Use `Open Manager` for additional controls.

Notes:

- The app normally runs without a Dock icon.
- The quick palette can also be opened with Shift + Command + Space by default.
- The floating windows are implemented with public AppKit `NSPanel` APIs.
- The app stores memo state locally on the device.
