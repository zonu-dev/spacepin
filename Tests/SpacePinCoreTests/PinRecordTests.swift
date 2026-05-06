import CoreGraphics
import XCTest
@testable import SpacePinCore

final class PinRecordTests: XCTestCase {
    func testColorPresetCountIsTwelve() {
        XCTAssertEqual(NoteColorPreset.allCases.count, 12)
    }

    func testBlankNoteUsesFallbackTitle() {
        let record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 200),
            noteText: " \n "
        )

        XCTAssertEqual(record.displayTitle, "Untitled")
    }

    func testDuplicateOffsetsFrameAndKeepsPayload() {
        let original = PinRecord.makeImage(
            frame: CGRect(x: 100, y: 120, width: 240, height: 180),
            imageAssetFilename: "demo.png",
            sourceDisplayName: "demo.png"
        )

        let duplicate = original.duplicated()

        XCTAssertNotEqual(original.id, duplicate.id)
        XCTAssertEqual(duplicate.imageAssetFilename, "demo.png")
        XCTAssertEqual(duplicate.frame.x, original.frame.x + 24)
        XCTAssertEqual(duplicate.frame.y, original.frame.y - 24)
    }

    func testNoteDefaultsToSunflowerPreset() {
        let record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 200),
            noteText: "hello"
        )

        XCTAssertEqual(record.noteColorPreset, .sunflower)
        XCTAssertEqual(record.noteFontSize, 15)
    }

    func testDuplicatePreservesNoteColorPreset() {
        let record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 200),
            noteText: "hello",
            noteColorPreset: .lavender
        )

        let duplicate = record.duplicated()

        XCTAssertEqual(duplicate.noteColorPreset, .lavender)
    }

    func testDuplicatePreservesCustomTitle() {
        let record = PinRecord.makeImage(
            frame: CGRect(x: 10, y: 20, width: 300, height: 200),
            title: "Party Layout",
            imageAssetFilename: "hello.png",
            sourceDisplayName: "hello.png"
        )

        let duplicate = record.duplicated()

        XCTAssertEqual(duplicate.displayTitle, "Party Layout")
    }

    func testNewPinsStartExpandedAndRememberInitialSize() {
        let record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            noteText: "hello"
        )

        XCTAssertFalse(record.isCollapsed)
        XCTAssertFalse(record.isDocked)
        XCTAssertNil(record.dockOrder)
        XCTAssertNil(record.inventoryOrder)
        XCTAssertEqual(record.expandedWidth, 300)
        XCTAssertEqual(record.expandedHeight, 220)
    }

    func testDuplicatePreservesNoteFontSize() {
        let record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            noteText: "hello",
            noteFontSize: 22
        )

        let duplicate = record.duplicated()

        XCTAssertEqual(duplicate.noteFontSize, 22)
    }

    func testImageDefaultsTitleToSourceDisplayName() {
        let record = PinRecord.makeImage(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            imageAssetFilename: "sheet.png",
            sourceDisplayName: "sheet.png"
        )

        XCTAssertEqual(record.displayTitle, "sheet.png")
    }

    func testImagePinsDefaultFrameColorPresetIsGraphite() {
        let record = PinRecord.makeImage(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            imageAssetFilename: "sheet.png",
            sourceDisplayName: "sheet.png"
        )

        XCTAssertEqual(record.frameColorPreset, .graphite)
        XCTAssertNil(record.imageFrameColorPreset)
    }

    func testHeaderIconDefaultsToTitleInitial() {
        let noteRecord = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            noteText: "hello"
        )
        let imageRecord = PinRecord.makeImage(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            imageAssetFilename: "sheet.png",
            sourceDisplayName: "sheet.png"
        )

        XCTAssertEqual(noteRecord.headerIconSymbolName, "note.text")
        XCTAssertEqual(imageRecord.headerIconSymbolName, "photo")
        XCTAssertEqual(noteRecord.headerIconMode, .titleInitial)
        XCTAssertEqual(imageRecord.headerIconMode, .titleInitial)
    }

    func testDuplicatePreservesCustomImageFrameColorPreset() {
        var record = PinRecord.makeImage(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            imageAssetFilename: "sheet.png",
            sourceDisplayName: "sheet.png"
        )
        record.imageFrameColorPreset = .coral

        let duplicate = record.duplicated()

        XCTAssertEqual(duplicate.imageFrameColorPreset, .coral)
        XCTAssertEqual(duplicate.frameColorPreset, .coral)
    }

    func testDuplicatePreservesCustomHeaderIcon() {
        var record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            noteText: "hello"
        )
        record.iconSymbolName = "star"

        let duplicate = record.duplicated()

        XCTAssertEqual(duplicate.iconSymbolName, "star")
        XCTAssertEqual(duplicate.headerIconSymbolName, "star")
    }

    func testDuplicatePreservesTitleInitialHeaderMode() {
        var record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 300, height: 220),
            noteText: "hello"
        )
        record.headerIconMode = .titleInitial
        record.iconSymbolName = "lightbulb"

        let duplicate = record.duplicated()

        XCTAssertEqual(duplicate.headerIconMode, .titleInitial)
        XCTAssertEqual(duplicate.iconSymbolName, "lightbulb")
    }

    func testDuplicateClearsDockMembership() {
        var record = PinRecord.makeNote(
            frame: CGRect(x: 10, y: 20, width: 34, height: 34),
            noteText: "Docked"
        )
        record.isCollapsed = true
        record.isDocked = true
        record.dockOrder = 2
        record.inventoryOrder = 7

        let duplicate = record.duplicated()

        XCTAssertFalse(duplicate.isDocked)
        XCTAssertNil(duplicate.dockOrder)
        XCTAssertNil(duplicate.inventoryOrder)
        XCTAssertFalse(duplicate.isCollapsed)
    }
}
