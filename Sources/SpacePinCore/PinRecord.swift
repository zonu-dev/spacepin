import CoreGraphics
import Foundation

public enum PinKind: String, Codable, CaseIterable, Sendable {
    case note
    case image
}

public enum PinHeaderIconMode: String, Codable, CaseIterable, Sendable {
    case symbol
    case titleInitial
}

public enum NoteColorPreset: String, Codable, CaseIterable, Sendable {
    case sunflower
    case mint
    case sky
    case coral
    case lavender
    case graphite
    case rose
    case peach
    case sage
    case teal
    case indigo
    case espresso

    public var displayName: String {
        switch self {
        case .sunflower:
            return "Sunflower"
        case .mint:
            return "Mint"
        case .sky:
            return "Sky"
        case .coral:
            return "Coral"
        case .lavender:
            return "Lavender"
        case .graphite:
            return "Graphite"
        case .rose:
            return "Rose"
        case .peach:
            return "Peach"
        case .sage:
            return "Sage"
        case .teal:
            return "Teal"
        case .indigo:
            return "Indigo"
        case .espresso:
            return "Espresso"
        }
    }
}

public struct PinFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct PinRecord: Codable, Equatable, Identifiable, Sendable {
    public static let defaultNoteTitle = "Untitled"
    public static let defaultNoteFontSize = 15.0

    public var id: UUID
    public var kind: PinKind
    public var title: String
    public var frame: PinFrame
    public var opacity: Double
    public var clickThrough: Bool
    public var locked: Bool
    public var noteText: String
    public var noteFontSize: Double
    public var noteColorPreset: NoteColorPreset
    public var headerIconMode: PinHeaderIconMode
    public var iconSymbolName: String?
    public var inventoryOrder: Int?
    public var isDocked: Bool
    public var dockOrder: Int?
    public var imageFrameColorPreset: NoteColorPreset?
    public var isCollapsed: Bool
    public var expandedWidth: Double?
    public var expandedHeight: Double?
    public var imageAssetFilename: String?
    public var sourceDisplayName: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        kind: PinKind,
        title: String,
        frame: PinFrame,
        opacity: Double,
        clickThrough: Bool,
        locked: Bool,
        noteText: String,
        noteFontSize: Double,
        noteColorPreset: NoteColorPreset,
        headerIconMode: PinHeaderIconMode,
        iconSymbolName: String?,
        inventoryOrder: Int?,
        isDocked: Bool,
        dockOrder: Int?,
        imageFrameColorPreset: NoteColorPreset?,
        isCollapsed: Bool,
        expandedWidth: Double?,
        expandedHeight: Double?,
        imageAssetFilename: String?,
        sourceDisplayName: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.frame = frame
        self.opacity = opacity
        self.clickThrough = clickThrough
        self.locked = locked
        self.noteText = noteText
        self.noteFontSize = noteFontSize
        self.noteColorPreset = noteColorPreset
        self.headerIconMode = headerIconMode
        self.iconSymbolName = iconSymbolName
        self.inventoryOrder = inventoryOrder
        self.isDocked = isDocked
        self.dockOrder = dockOrder
        self.imageFrameColorPreset = imageFrameColorPreset
        self.isCollapsed = isCollapsed
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
        self.imageAssetFilename = imageAssetFilename
        self.sourceDisplayName = sourceDisplayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func makeNote(
        id: UUID = UUID(),
        frame: CGRect,
        title: String = "",
        noteText: String = "",
        noteFontSize: Double = PinRecord.defaultNoteFontSize,
        noteColorPreset: NoteColorPreset = .sunflower
    ) -> PinRecord {
        let timestamp = Date.spacePinNow

        return PinRecord(
            id: id,
            kind: .note,
            title: title,
            frame: PinFrame(frame),
            opacity: 1.0,
            clickThrough: false,
            locked: false,
            noteText: noteText,
            noteFontSize: noteFontSize,
            noteColorPreset: noteColorPreset,
            headerIconMode: .titleInitial,
            iconSymbolName: nil,
            inventoryOrder: nil,
            isDocked: false,
            dockOrder: nil,
            imageFrameColorPreset: nil,
            isCollapsed: false,
            expandedWidth: frame.width,
            expandedHeight: frame.height,
            imageAssetFilename: nil,
            sourceDisplayName: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    public static func makeImage(
        id: UUID = UUID(),
        frame: CGRect,
        title: String? = nil,
        imageAssetFilename: String,
        sourceDisplayName: String? = nil
    ) -> PinRecord {
        let timestamp = Date.spacePinNow
        let resolvedTitle = normalizedRawTitle(title)

        return PinRecord(
            id: id,
            kind: .image,
            title: resolvedTitle,
            frame: PinFrame(frame),
            opacity: 1.0,
            clickThrough: false,
            locked: false,
            noteText: "",
            noteFontSize: PinRecord.defaultNoteFontSize,
            noteColorPreset: .sunflower,
            headerIconMode: .titleInitial,
            iconSymbolName: nil,
            inventoryOrder: nil,
            isDocked: false,
            dockOrder: nil,
            imageFrameColorPreset: nil,
            isCollapsed: false,
            expandedWidth: frame.width,
            expandedHeight: frame.height,
            imageAssetFilename: imageAssetFilename,
            sourceDisplayName: sourceDisplayName,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    public var defaultTitle: String {
        switch kind {
        case .note:
            return PinRecord.defaultNoteTitle
        case .image:
            return sourceDisplayName.flatMap {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? "Image Pin"
        }
    }

    public var displayTitle: String {
        Self.normalizedTitle(title, fallback: defaultTitle)
    }

    public func duplicated(
        newID: UUID = UUID(),
        translatedBy offset: CGSize = CGSize(width: 24, height: -24)
    ) -> PinRecord {
        let timestamp = Date.spacePinNow
        let translatedFrame = CGRect(
            x: frame.cgRect.origin.x + offset.width,
            y: frame.cgRect.origin.y + offset.height,
            width: frame.cgRect.size.width,
            height: frame.cgRect.size.height
        )

        return PinRecord(
            id: newID,
            kind: kind,
            title: title,
            frame: PinFrame(translatedFrame),
            opacity: opacity,
            clickThrough: clickThrough,
            locked: locked,
            noteText: noteText,
            noteFontSize: noteFontSize,
            noteColorPreset: noteColorPreset,
            headerIconMode: headerIconMode,
            iconSymbolName: iconSymbolName,
            inventoryOrder: nil,
            isDocked: false,
            dockOrder: nil,
            imageFrameColorPreset: imageFrameColorPreset,
            isCollapsed: false,
            expandedWidth: expandedWidth ?? frame.width,
            expandedHeight: expandedHeight ?? frame.height,
            imageAssetFilename: imageAssetFilename,
            sourceDisplayName: sourceDisplayName,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case frame
        case opacity
        case clickThrough
        case locked
        case noteText
        case noteFontSize
        case noteColorPreset
        case headerIconMode
        case iconSymbolName
        case inventoryOrder
        case isDocked
        case dockOrder
        case imageFrameColorPreset
        case isCollapsed
        case expandedWidth
        case expandedHeight
        case imageAssetFilename
        case sourceDisplayName
        case createdAt
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(PinKind.self, forKey: .kind)
        noteText = try container.decode(String.self, forKey: .noteText)
        sourceDisplayName = try container.decodeIfPresent(String.self, forKey: .sourceDisplayName)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? Self.legacyTitle(kind: kind, noteText: noteText, sourceDisplayName: sourceDisplayName)
        frame = try container.decode(PinFrame.self, forKey: .frame)
        opacity = try container.decode(Double.self, forKey: .opacity)
        clickThrough = try container.decode(Bool.self, forKey: .clickThrough)
        locked = try container.decode(Bool.self, forKey: .locked)
        noteFontSize = try container.decodeIfPresent(Double.self, forKey: .noteFontSize) ?? Self.defaultNoteFontSize
        noteColorPreset = try container.decodeIfPresent(NoteColorPreset.self, forKey: .noteColorPreset) ?? .sunflower
        headerIconMode = try container.decodeIfPresent(PinHeaderIconMode.self, forKey: .headerIconMode) ?? .symbol
        iconSymbolName = try container.decodeIfPresent(String.self, forKey: .iconSymbolName)
        inventoryOrder = try container.decodeIfPresent(Int.self, forKey: .inventoryOrder)
        isDocked = try container.decodeIfPresent(Bool.self, forKey: .isDocked) ?? false
        dockOrder = try container.decodeIfPresent(Int.self, forKey: .dockOrder)
        imageFrameColorPreset = try container.decodeIfPresent(NoteColorPreset.self, forKey: .imageFrameColorPreset)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        expandedWidth = try container.decodeIfPresent(Double.self, forKey: .expandedWidth) ?? frame.width
        expandedHeight = try container.decodeIfPresent(Double.self, forKey: .expandedHeight)
        imageAssetFilename = try container.decodeIfPresent(String.self, forKey: .imageAssetFilename)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(frame, forKey: .frame)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(clickThrough, forKey: .clickThrough)
        try container.encode(locked, forKey: .locked)
        try container.encode(noteText, forKey: .noteText)
        try container.encode(noteFontSize, forKey: .noteFontSize)
        try container.encode(noteColorPreset, forKey: .noteColorPreset)
        try container.encode(headerIconMode, forKey: .headerIconMode)
        try container.encodeIfPresent(iconSymbolName, forKey: .iconSymbolName)
        try container.encodeIfPresent(inventoryOrder, forKey: .inventoryOrder)
        try container.encode(isDocked, forKey: .isDocked)
        try container.encodeIfPresent(dockOrder, forKey: .dockOrder)
        try container.encodeIfPresent(imageFrameColorPreset, forKey: .imageFrameColorPreset)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encodeIfPresent(expandedWidth, forKey: .expandedWidth)
        try container.encodeIfPresent(expandedHeight, forKey: .expandedHeight)
        try container.encodeIfPresent(imageAssetFilename, forKey: .imageAssetFilename)
        try container.encodeIfPresent(sourceDisplayName, forKey: .sourceDisplayName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func normalizedTitle(_ title: String?, fallback: String) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? fallback : trimmedTitle
    }

    private static func normalizedRawTitle(_ title: String?) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func legacyTitle(
        kind: PinKind,
        noteText: String,
        sourceDisplayName: String?
    ) -> String {
        switch kind {
        case .note:
            let firstLine = noteText
                .split(whereSeparator: \.isNewline)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return normalizedTitle(firstLine, fallback: defaultNoteTitle)
        case .image:
            return normalizedTitle(sourceDisplayName, fallback: "Image Pin")
        }
    }
}

public extension PinRecord {
    static func defaultHeaderIconSymbolName(for kind: PinKind) -> String {
        switch kind {
        case .note:
            return "note.text"
        case .image:
            return "photo"
        }
    }

    var headerIconSymbolName: String {
        let trimmedSymbolName = iconSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSymbolName.isEmpty ? Self.defaultHeaderIconSymbolName(for: kind) : trimmedSymbolName
    }

    var frameColorPreset: NoteColorPreset {
        switch kind {
        case .note:
            return noteColorPreset
        case .image:
            return imageFrameColorPreset ?? .graphite
        }
    }

    var isDockedPin: Bool {
        isDocked
    }

    var isDockedNote: Bool {
        kind == .note && isDocked
    }
}

private extension Date {
    static var spacePinNow: Date {
        let timestamp = Date().timeIntervalSince1970
        let roundedMilliseconds = (timestamp * 1000).rounded() / 1000
        return Date(timeIntervalSince1970: roundedMilliseconds)
    }
}
