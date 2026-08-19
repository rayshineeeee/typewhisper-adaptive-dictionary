import Foundation
import XCTest
@testable import AdaptiveDictionaryCore

final class InsertionEditResolverTests: XCTestCase {
    func testLocatesInsertionImmediatelyBeforeCursor() {
        let baseline = "Existing text open linear"
        let cursor = (baseline as NSString).length

        XCTAssertEqual(
            InsertionEditResolver.locateInsertedRange(
                text: "open linear",
                in: baseline,
                selectedRange: NSRange(location: cursor, length: 0)
            ),
            NSRange(location: 14, length: 11)
        )
    }

    func testChoosesOccurrenceNearestCursor() {
        let baseline = "linear first, then linear"

        XCTAssertEqual(
            InsertionEditResolver.locateInsertedRange(
                text: "linear",
                in: baseline,
                selectedRange: NSRange(location: (baseline as NSString).length, length: 0)
            ),
            NSRange(location: 19, length: 6)
        )
    }

    func testReconstructsCorrectionInsideInsertedRange() {
        let baseline = "prefix open linear suffix"
        let edited = "prefix open Linear suffix"

        XCTAssertEqual(
            InsertionEditResolver.correctedInsertedText(
                baselineText: baseline,
                editedText: edited,
                insertedRange: NSRange(location: 7, length: 11)
            ),
            "open Linear"
        )
    }

    func testHandlesUnicodeBeforeInsertedRange() {
        let baseline = "👋 open linear"
        let edited = "👋 open Linear"
        let location = ("👋 " as NSString).length

        XCTAssertEqual(
            InsertionEditResolver.correctedInsertedText(
                baselineText: baseline,
                editedText: edited,
                insertedRange: NSRange(location: location, length: ("open linear" as NSString).length)
            ),
            "open Linear"
        )
    }

    func testRejectsEditOutsideInsertedRange() {
        XCTAssertNil(
            InsertionEditResolver.correctedInsertedText(
                baselineText: "prefix open linear",
                editedText: "Prefix open linear",
                insertedRange: NSRange(location: 7, length: 11)
            )
        )
    }

    func testTrimsCommitNewline() {
        XCTAssertEqual(
            InsertionEditResolver.correctedInsertedText(
                baselineText: "open linear",
                editedText: "open Linear\n",
                insertedRange: NSRange(location: 0, length: 11)
            ),
            "open Linear"
        )
    }
}
