// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import XCTest
import CoreGraphics
@testable import PresenterKit

final class GeometryTests: XCTestCase {

    func testFittedRectLetterboxesWideContentInSquare() {
        // 16:9 into a square container → full width, bars top & bottom.
        let r = fittedRect(aspect: 16.0 / 9.0, in: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(r.width, 1000, accuracy: 0.001)
        XCTAssertEqual(r.height, 562.5, accuracy: 0.01)
        XCTAssertEqual(r.minX, 0, accuracy: 0.001)
        XCTAssertEqual(r.minY, 218.75, accuracy: 0.01)   // centered vertically
    }

    func testFittedRectPillarboxesTallContentInWideContainer() {
        // 1:1 into a 2:1 container → full height, bars left & right.
        let r = fittedRect(aspect: 1.0, in: CGSize(width: 1000, height: 500))
        XCTAssertEqual(r.width, 500, accuracy: 0.001)
        XCTAssertEqual(r.height, 500, accuracy: 0.001)
        XCTAssertEqual(r.minX, 250, accuracy: 0.001)   // centered horizontally
        XCTAssertEqual(r.minY, 0, accuracy: 0.001)
    }

    func testFittedRectExactAspectFillsContainer() {
        let r = fittedRect(aspect: 2.0, in: CGSize(width: 1000, height: 500))
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 1000, height: 500))
    }

    func testFittedRectInvalidAspectReturnsFullSize() {
        let size = CGSize(width: 1000, height: 500)
        XCTAssertEqual(fittedRect(aspect: 0, in: size), CGRect(origin: .zero, size: size))
        XCTAssertEqual(fittedRect(aspect: -3, in: size), CGRect(origin: .zero, size: size))
    }

    func testFittedSizeMatchesFittedRect() {
        XCTAssertEqual(fittedSize(aspect: 16.0 / 9.0, in: CGSize(width: 1000, height: 1000)),
                       CGSize(width: 1000, height: 562.5))
        XCTAssertEqual(fittedSize(aspect: 1.0, in: CGSize(width: 1000, height: 500)),
                       CGSize(width: 500, height: 500))
    }

    func testClamp() {
        XCTAssertEqual(clamp(0.5), 0.5)
        XCTAssertEqual(clamp(1.5), 1.0)
        XCTAssertEqual(clamp(-0.2), 0.0)
        XCTAssertEqual(clamp(20, 0, 10), 10)
        XCTAssertEqual(clamp(5, 0, 10), 5)
    }

    func testElapsedString() {
        XCTAssertEqual(elapsedString(0), "00:00:00")
        XCTAssertEqual(elapsedString(59), "00:00:59")
        XCTAssertEqual(elapsedString(3661), "01:01:01")
        XCTAssertEqual(elapsedString(-5), "00:00:00")   // clamped at zero
    }
}
