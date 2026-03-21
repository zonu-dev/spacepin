import AppKit
import SpacePinCore
import SwiftUI

struct NoteTheme {
    let headerBackground: NSColor
    let bodyBackground: NSColor
    let headerText: NSColor
    let bodyText: NSColor
    let selectionBackground: NSColor
    let selectionText: NSColor
    let border: NSColor
    let swatch: NSColor
}

extension NoteColorPreset {
    var theme: NoteTheme {
        switch self {
        case .sunflower:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.96, green: 0.87, blue: 0.41, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.84, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.24, green: 0.19, blue: 0.05, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.20, green: 0.17, blue: 0.09, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.08, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.12),
                swatch: NSColor(calibratedRed: 0.92, green: 0.76, blue: 0.16, alpha: 1.0)
            )
        case .mint:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.54, green: 0.86, blue: 0.70, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.92, green: 0.98, blue: 0.95, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.07, green: 0.26, blue: 0.20, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.18, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.35, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.34, green: 0.75, blue: 0.56, alpha: 1.0)
            )
        case .sky:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.53, green: 0.74, blue: 0.95, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.93, green: 0.97, blue: 1.0, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.07, green: 0.20, blue: 0.36, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.32, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.20, green: 0.39, blue: 0.69, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.35, green: 0.63, blue: 0.94, alpha: 1.0)
            )
        case .coral:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.58, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.92, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.38, green: 0.12, blue: 0.09, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.30, green: 0.12, blue: 0.10, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.67, green: 0.25, blue: 0.21, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.93, green: 0.46, blue: 0.38, alpha: 1.0)
            )
        case .lavender:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.77, green: 0.68, blue: 0.95, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.96, green: 0.94, blue: 1.0, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.40, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.33, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.43, green: 0.29, blue: 0.71, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.64, green: 0.53, blue: 0.91, alpha: 1.0)
            )
        case .graphite:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.29, green: 0.31, blue: 0.36, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.23, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.97, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.39, green: 0.62, blue: 0.95, alpha: 0.95),
                selectionText: .white,
                border: NSColor.white.withAlphaComponent(0.14),
                swatch: NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.37, alpha: 1.0)
            )
        }
    }

    var swiftUIColor: Color {
        Color(nsColor: theme.swatch)
    }
}
