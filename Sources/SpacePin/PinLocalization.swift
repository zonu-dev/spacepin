import SpacePinCore

extension L10n {
    static func noteColorName(_ preset: NoteColorPreset) -> String {
        text("color.\(preset.rawValue)", fallback: preset.displayName)
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
