import Foundation

public struct PinRepository {
    public let rootDirectory: URL
    public let fileManager: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public var pinsFileURL: URL {
        rootDirectory.appendingPathComponent("pins.json", isDirectory: false)
    }

    public func load() throws -> [PinRecord] {
        guard fileManager.fileExists(atPath: pinsFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: pinsFileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder.spacePin.decode([PinRecord].self, from: data)
    }

    public func save(_ pins: [PinRecord]) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try JSONEncoder.spacePin.encode(pins)
        try data.write(to: pinsFileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var spacePin: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .formatted(.spacePin)
        return encoder
    }
}

private extension JSONDecoder {
    static var spacePin: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(.spacePin)
        return decoder
    }
}

private extension DateFormatter {
    static let spacePin: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}
