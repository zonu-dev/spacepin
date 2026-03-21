import Foundation

public struct ImageAssetStore {
    public struct ImportedImageAsset: Equatable {
        public let filename: String
        public let fileURL: URL

        public init(filename: String, fileURL: URL) {
            self.filename = filename
            self.fileURL = fileURL
        }
    }

    public let rootDirectory: URL
    public let fileManager: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public var assetsDirectory: URL {
        rootDirectory.appendingPathComponent("images", isDirectory: true)
    }

    public func importImage(at sourceURL: URL) throws -> ImportedImageAsset {
        try fileManager.createDirectory(
            at: assetsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let pathExtension = sourceURL.pathExtension.isEmpty ? "img" : sourceURL.pathExtension.lowercased()
        let filename = "\(UUID().uuidString).\(pathExtension)"
        let destinationURL = assetsDirectory.appendingPathComponent(filename, isDirectory: false)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return ImportedImageAsset(filename: filename, fileURL: destinationURL)
    }

    public func fileURL(for filename: String) -> URL {
        assetsDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    public func removeUnreferencedAssets(keeping referencedFilenames: Set<String>) throws {
        guard fileManager.fileExists(atPath: assetsDirectory.path) else {
            return
        }

        let assetURLs = try fileManager.contentsOfDirectory(
            at: assetsDirectory,
            includingPropertiesForKeys: nil
        )

        for assetURL in assetURLs where !referencedFilenames.contains(assetURL.lastPathComponent) {
            try? fileManager.removeItem(at: assetURL)
        }
    }
}
