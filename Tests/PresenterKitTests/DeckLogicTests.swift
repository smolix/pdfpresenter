// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import XCTest
import CoreGraphics
@testable import PresenterKit

final class DeckLogicTests: XCTestCase {

    // MARK: Split detection

    func testDetectSplitThresholds() {
        // Beamer notes deck (~2.13:1): auto-detected and wide.
        XCTAssertEqual(detectSplit(cropBoxAspect: 2.13), SplitDetection(detectedSplit: true, pageIsWide: true))
        // Wide-ish but under the auto threshold: not auto, but wide enough to force.
        XCTAssertEqual(detectSplit(cropBoxAspect: 1.95), SplitDetection(detectedSplit: false, pageIsWide: true))
        // 16:9 single slide (1.78): neither.
        XCTAssertEqual(detectSplit(cropBoxAspect: 16.0 / 9.0), SplitDetection(detectedSplit: false, pageIsWide: false))
        // Empty / unreadable page.
        XCTAssertEqual(detectSplit(cropBoxAspect: 0), SplitDetection(detectedSplit: false, pageIsWide: false))
    }

    func testDetectSplitBoundariesAreStrict() {
        // Exactly on a threshold does not trip it (strictly greater-than).
        XCTAssertFalse(detectSplit(cropBoxAspect: notesSplitAspect).detectedSplit)
        XCTAssertFalse(detectSplit(cropBoxAspect: wideEnoughToSplitAspect).pageIsWide)
    }

    func testIsSplitActiveByMode() {
        let wideDeck = SplitDetection(detectedSplit: true, pageIsWide: true)
        let narrow = SplitDetection(detectedSplit: false, pageIsWide: false)
        let forcibleOnly = SplitDetection(detectedSplit: false, pageIsWide: true)

        // auto follows detection
        XCTAssertTrue(isSplitActive(mode: .auto, detection: wideDeck))
        XCTAssertFalse(isSplitActive(mode: .auto, detection: forcibleOnly))

        // single never splits
        XCTAssertFalse(isSplitActive(mode: .single, detection: wideDeck))

        // splitRight forces, but only on a wide page
        XCTAssertTrue(isSplitActive(mode: .splitRight, detection: forcibleOnly))
        XCTAssertFalse(isSplitActive(mode: .splitRight, detection: narrow))
    }

    // MARK: Slide / notes regions

    func testSlideAndNotesRegions() {
        let box = CGSize(width: 1000, height: 750)

        XCTAssertEqual(slideRegion(cropBox: box, split: false), CGRect(x: 0, y: 0, width: 1000, height: 750))
        XCTAssertNil(notesRegion(cropBox: box, split: false))

        XCTAssertEqual(slideRegion(cropBox: box, split: true), CGRect(x: 0, y: 0, width: 500, height: 750))
        XCTAssertEqual(notesRegion(cropBox: box, split: true), CGRect(x: 500, y: 0, width: 500, height: 750))
    }

    // MARK: Page-label lookup

    func testResolveSlideLabel() {
        let labels = ["1", "2", "3", "4"]
        XCTAssertEqual(resolveSlideLabel("3", in: labels), 2)
        XCTAssertEqual(resolveSlideLabel("  4 ", in: labels), 3)   // trims whitespace
        XCTAssertNil(resolveSlideLabel("9", in: labels))
        XCTAssertNil(resolveSlideLabel("", in: labels))
        XCTAssertNil(resolveSlideLabel("   ", in: labels))
    }

    func testResolveSlideLabelHonorsCustomLabelsAndFirstMatch() {
        // A title page + restarted numbering: the printed "1" is index 2.
        XCTAssertEqual(resolveSlideLabel("1", in: ["i", "ii", "1", "2"]), 2)
        // Overlay frames repeat a label; the first wins.
        XCTAssertEqual(resolveSlideLabel("7", in: ["6", "7", "7", "8"]), 1)
    }

    // MARK: Notes sidecar parsing

    func testParseSlideNotesBasic() {
        let notes = parseSlideNotes("# 1\nHello\n# 2\nWorld")
        XCTAssertEqual(notes, [1: "Hello", 2: "World"])
    }

    func testParseSlideNotesHeaderVariantsAndTrimming() {
        let text = """
        intro text before any header is ignored
        ## Slide 3
          first line
        second line

        # 4 a title after the number
        body four
        """
        let notes = parseSlideNotes(text)
        XCTAssertEqual(notes[3], "first line\nsecond line")   // leading/trailing blank lines trimmed
        XCTAssertEqual(notes[4], "body four")                 // "# 4 a title…" keys on 4
        XCTAssertNil(notes[1])                                // pre-header text dropped
    }

    func testParseSlideNotesEmptyAndHeaderless() {
        XCTAssertEqual(parseSlideNotes(""), [:])
        XCTAssertEqual(parseSlideNotes("just some prose\nwith no headers"), [:])
    }
}
