import Foundation

public enum SpacePinPaths {
    public static func defaultRootDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return baseDirectory.appendingPathComponent("SpacePin", isDirectory: true)
    }
}
