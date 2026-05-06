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
        case .rose:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.93, green: 0.56, blue: 0.69, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.99, green: 0.92, blue: 0.95, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.41, green: 0.10, blue: 0.20, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.35, green: 0.11, blue: 0.20, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.72, green: 0.22, blue: 0.40, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.89, green: 0.37, blue: 0.57, alpha: 1.0)
            )
        case .peach:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.56, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.90, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.40, green: 0.17, blue: 0.05, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.32, green: 0.16, blue: 0.08, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.76, green: 0.38, blue: 0.13, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.96, green: 0.59, blue: 0.33, alpha: 1.0)
            )
        case .sage:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.67, green: 0.80, blue: 0.60, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.95, green: 0.98, blue: 0.93, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.15, green: 0.26, blue: 0.12, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.16, green: 0.25, blue: 0.14, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.30, green: 0.49, blue: 0.24, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.49, green: 0.68, blue: 0.41, alpha: 1.0)
            )
        case .teal:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.34, green: 0.73, blue: 0.72, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.89, green: 0.97, blue: 0.96, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.05, green: 0.24, blue: 0.25, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.07, green: 0.22, blue: 0.22, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.09, green: 0.45, blue: 0.47, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.18, green: 0.64, blue: 0.64, alpha: 1.0)
            )
        case .indigo:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.49, green: 0.55, blue: 0.92, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.93, green: 0.94, blue: 1.0, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.35, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.32, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.69, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.86, alpha: 1.0)
            )
        case .espresso:
            return NoteTheme(
                headerBackground: NSColor(calibratedRed: 0.52, green: 0.39, blue: 0.31, alpha: 1.0),
                bodyBackground: NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.88, alpha: 1.0),
                headerText: NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.91, alpha: 1.0),
                bodyText: NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.12, alpha: 1.0),
                selectionBackground: NSColor(calibratedRed: 0.46, green: 0.28, blue: 0.19, alpha: 0.92),
                selectionText: .white,
                border: NSColor.black.withAlphaComponent(0.1),
                swatch: NSColor(calibratedRed: 0.47, green: 0.33, blue: 0.24, alpha: 1.0)
            )
        }
    }

    var swiftUIColor: Color {
        Color(nsColor: theme.swatch)
    }
}
