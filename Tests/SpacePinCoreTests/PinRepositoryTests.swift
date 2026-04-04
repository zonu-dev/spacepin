import CoreGraphics
import Foundation
import XCTest
@testable import SpacePinCore

final class PinRepositoryTests: XCTestCase {
    func testLoadMissingStoreReturnsEmptyArray() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = PinRepository(rootDirectory: rootDirectory)

        XCTAssertEqual(try repository.load(), [])
    }

    func testSaveAndLoadRoundTrip() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = PinRepository(rootDirectory: rootDirectory)
        let pins = [
            PinRecord.makeNote(
                frame: CGRect(x: 20, y: 40, width: 320, height: 240),
                noteText: "Remember this",
                noteColorPreset: .mint
            ),
            PinRecord.makeImage(
                frame: CGRect(x: 80, y: 120, width: 260, height: 200),
                imageAssetFilename: "image.png",
                sourceDisplayName: "image.png"
            ),
        ]

        try repository.save(pins)

        XCTAssertEqual(try repository.load(), pins)
    }

    func testDecodeLegacyPinWithoutNoteColorPresetFallsBackToSunflower() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = PinRepository(rootDirectory: rootDirectory)
        let legacyJSON = """
        [
          {
            "clickThrough" : false,
            "createdAt" : "2026-03-22T00:00:00.000Z",
            "frame" : {
              "height" : 240,
              "width" : 320,
              "x" : 20,
              "y" : 40
            },
            "id" : "11111111-1111-1111-1111-111111111111",
            "imageAssetFilename" : null,
            "kind" : "note",
            "locked" : false,
            "noteText" : "legacy",
            "opacity" : 1,
            "sourceDisplayName" : null,
            "updatedAt" : "2026-03-22T00:00:00.000Z"
          }
        ]
        """

        try XCTUnwrap(legacyJSON.data(using: .utf8)).write(to: repository.pinsFileURL)

        let loaded = try repository.load()

        XCTAssertEqual(loaded.first?.noteColorPreset, .sunflower)
        XCTAssertEqual(loaded.first?.noteFontSize, 15)
        XCTAssertEqual(loaded.first?.isCollapsed, false)
        XCTAssertEqual(loaded.first?.displayTitle, "legacy")
    }

    func testCollapsedPinRoundTripsExpandedHeight() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = PinRepository(rootDirectory: rootDirectory)
        var record = PinRecord.makeNote(
            frame: CGRect(x: 20, y: 40, width: 320, height: 34),
            noteText: "remember size",
            noteColorPreset: .sky
        )
        record.isCollapsed = true
        record.expandedHeight = 260

        try repository.save([record])

        let loaded = try repository.load()

        XCTAssertEqual(loaded.first?.isCollapsed, true)
        XCTAssertEqual(loaded.first?.expandedHeight, 260)
    }

    func testCustomTitleRoundTrips() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = PinRepository(rootDirectory: rootDirectory)
        let record = PinRecord.makeImage(
            frame: CGRect(x: 20, y: 40, width: 320, height: 200),
            title: "Reference Sheet",
            imageAssetFilename: "sheet.png",
            sourceDisplayName: "sheet.png"
        )

        try repository.save([record])

        let loaded = try repository.load()

        XCTAssertEqual(loaded.first?.displayTitle, "Reference Sheet")
    }

    func testNoteFontSizeRoundTrips() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = PinRepository(rootDirectory: rootDirectory)
        let record = PinRecord.makeNote(
            frame: CGRect(x: 20, y: 40, width: 320, height: 240),
            noteText: "Large type",
            noteFontSize: 24,
            noteColorPreset: .mint
        )

        try repository.save([record])

        let loaded = try repository.load()

        XCTAssertEqual(loaded.first?.noteFontSize, 24)
    }

    func testBlankRawTitleRoundTripsWithoutFreezingFallbackTitle() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let repository = PinRepository(rootDirectory: rootDirectory)
        let record = PinRecord.makeNote(
            frame: CGRect(x: 20, y: 40, width: 320, height: 240),
            title: "",
            noteText: ""
        )

        try repository.save([record])

        let loaded = try repository.load()

        XCTAssertEqual(loaded.first?.title, "")
        XCTAssertEqual(loaded.first?.displayTitle, "Untitled")
    }
}
