// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import XCTest
@testable import PresenterKit

final class RuntimeTests: XCTestCase {

    // MARK: shouldKeepAwake

    func testShouldKeepAwakeTruthTable() {
        XCTAssertTrue(shouldKeepAwake(presenting: true, lowPower: false))   // the only awake case
        XCTAssertFalse(shouldKeepAwake(presenting: true, lowPower: true))   // yield to Low Power Mode
        XCTAssertFalse(shouldKeepAwake(presenting: false, lowPower: false)) // not presenting
        XCTAssertFalse(shouldKeepAwake(presenting: false, lowPower: true))
    }

    // MARK: FileStabilityGate

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ secs: TimeInterval) -> Date { t0.addingTimeInterval(secs) }

    func testUnchangedFileNeverReloads() {
        var gate = FileStabilityGate<Int>(stableFor: 5, loaded: 100)
        XCTAssertFalse(gate.observe(100, now: at(0)))
        XCTAssertFalse(gate.observe(100, now: at(10)))
    }

    func testReloadsOnceAfterFileSettles() {
        var gate = FileStabilityGate<Int>(stableFor: 5, loaded: 100)
        XCTAssertFalse(gate.observe(200, now: at(0)))   // change noticed; clock starts
        XCTAssertFalse(gate.observe(200, now: at(3)))   // still within the window
        XCTAssertFalse(gate.observe(200, now: at(4.9)))
        XCTAssertTrue(gate.observe(200, now: at(5)))    // settled → fire, exactly once
        // Without a markLoaded() the same steady value re-arms and fires again later.
        XCTAssertFalse(gate.observe(200, now: at(6)))
        XCTAssertTrue(gate.observe(200, now: at(11)))
    }

    func testMarkLoadedStopsReDetection() {
        var gate = FileStabilityGate<Int>(stableFor: 5, loaded: 100)
        _ = gate.observe(200, now: at(0))
        XCTAssertTrue(gate.observe(200, now: at(5)))
        gate.markLoaded(200)                            // caller reloaded the new version
        XCTAssertFalse(gate.observe(200, now: at(6)))   // now matches loaded → quiet
        XCTAssertFalse(gate.observe(200, now: at(100)))
    }

    func testChangingAgainRestartsTheClock() {
        var gate = FileStabilityGate<Int>(stableFor: 5, loaded: 100)
        XCTAssertFalse(gate.observe(200, now: at(0)))
        XCTAssertFalse(gate.observe(300, now: at(2)))   // changed again at t+2 → clock restarts
        XCTAssertFalse(gate.observe(300, now: at(5)))   // only 3s of stability
        XCTAssertTrue(gate.observe(300, now: at(7)))    // 5s since the last change
    }

    func testUnreadableSignatureDoesNotResetClock() {
        var gate = FileStabilityGate<Int>(stableFor: 5, loaded: 100)
        XCTAssertFalse(gate.observe(200, now: at(0)))
        XCTAssertFalse(gate.observe(nil, now: at(1)))   // mid-write, momentarily unreadable
        XCTAssertFalse(gate.observe(nil, now: at(3)))
        XCTAssertTrue(gate.observe(200, now: at(5)))     // clock from t0 survived the gaps
    }

    func testResetPendingDropsInProgressChange() {
        var gate = FileStabilityGate<Int>(stableFor: 5, loaded: 100)
        XCTAssertFalse(gate.observe(200, now: at(0)))
        gate.resetPending()                              // e.g. watching paused
        XCTAssertFalse(gate.observe(200, now: at(6)))    // clock restarts from here
        XCTAssertTrue(gate.observe(200, now: at(11)))
    }
}
