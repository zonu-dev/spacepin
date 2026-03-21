import Foundation
import XCTest
@testable import SpacePinCore

final class ImageAssetStoreTests: XCTestCase {
    func testImportCopiesFileAndCleanupRemovesUnreferencedAssets() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let sourceA = rootDirectory.appendingPathComponent("source-a.dat")
        let sourceB = rootDirectory.appendingPathComponent("source-b.dat")
        try Data("a".utf8).write(to: sourceA)
        try Data("b".utf8).write(to: sourceB)

        let store = ImageAssetStore(rootDirectory: rootDirectory)
        let importedA = try store.importImage(at: sourceA)
        let importedB = try store.importImage(at: sourceB)

        XCTAssertTrue(FileManager.default.fileExists(atPath: importedA.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedB.fileURL.path))

        try store.removeUnreferencedAssets(keeping: [importedA.filename])

        XCTAssertTrue(FileManager.default.fileExists(atPath: importedA.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedB.fileURL.path))
    }
}
