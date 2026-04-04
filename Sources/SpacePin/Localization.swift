import Foundation
import SpacePinCore

enum L10n {
    private static let fallbackLocaleIdentifier = "en"
    private static let supportedLocaleIdentifiers = [
        "en",
        "ja",
        "fr",
        "de",
        "es",
        "pt-BR",
        "ru",
        "ar",
        "tr",
        "ko",
        "zh-Hans",
        "zh-Hant",
        "hi",
        "id",
        "th",
        "vi",
        "uk",
        "ms",
    ]

    private static let catalog: [String: [String: String]] = loadCatalog()
    private static let localeIdentifier = resolveLocaleIdentifier(from: Locale.preferredLanguages)

    static var currentLocale: Locale {
        Locale(identifier: localeIdentifier)
    }

    static func text(_ key: String, fallback: String) -> String {
        catalog[localeIdentifier]?[key]
            ?? catalog[fallbackLocaleIdentifier]?[key]
            ?? fallback
    }

    static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: text(key, fallback: fallback), locale: currentLocale, arguments: arguments)
    }

    static func noteColorName(_ preset: NoteColorPreset) -> String {
        text("color.\(preset.rawValue)", fallback: preset.displayName)
    }

    private static func loadCatalog() -> [String: [String: String]] {
        guard
            let url = resourceBundle.url(forResource: "localizations", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else {
            return [:]
        }

        return catalog
    }

    private static func resolveLocaleIdentifier(from preferredLanguages: [String]) -> String {
        for preferredLanguage in preferredLanguages {
            if let supportedLocaleIdentifier = supportedLocaleIdentifier(for: preferredLanguage) {
                return supportedLocaleIdentifier
            }
        }

        return fallbackLocaleIdentifier
    }

    private static func supportedLocaleIdentifier(for preferredLanguage: String) -> String? {
        let normalizedIdentifier = preferredLanguage.replacingOccurrences(of: "_", with: "-")

        if supportedLocaleIdentifiers.contains(normalizedIdentifier) {
            return normalizedIdentifier
        }

        let loweredIdentifier = normalizedIdentifier.lowercased()
        if loweredIdentifier.hasPrefix("zh") {
            if loweredIdentifier.contains("hant")
                || loweredIdentifier.hasSuffix("-tw")
                || loweredIdentifier.hasSuffix("-hk")
                || loweredIdentifier.hasSuffix("-mo")
            {
                return "zh-Hant"
            }

            return "zh-Hans"
        }

        if loweredIdentifier.hasPrefix("pt") {
            return "pt-BR"
        }

        let languageCode = normalizedIdentifier
            .split(separator: "-", maxSplits: 1)
            .first?
            .lowercased()

        switch languageCode {
        case "en":
            return "en"
        case "ja":
            return "ja"
        case "fr":
            return "fr"
        case "de":
            return "de"
        case "es":
            return "es"
        case "ru":
            return "ru"
        case "ar":
            return "ar"
        case "tr":
            return "tr"
        case "ko":
            return "ko"
        case "hi":
            return "hi"
        case "id":
            return "id"
        case "th":
            return "th"
        case "vi":
            return "vi"
        case "uk":
            return "uk"
        case "ms":
            return "ms"
        default:
            return nil
        }
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}

extension PinRecord {
    var localizedDefaultTitle: String {
        switch kind {
        case .note:
            return L10n.text("pin.title.untitled", fallback: PinRecord.defaultNoteTitle)
        case .image:
            if let sourceDisplayName {
                let trimmed = sourceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            return L10n.text("pin.title.image", fallback: "Image Pin")
        }
    }

    var localizedDisplayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? localizedDefaultTitle : trimmedTitle
    }
}
