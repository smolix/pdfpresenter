// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import XCTest
import CoreGraphics
@testable import PresenterKit

final class ProtocolTests: XCTestCase {

    // MARK: Timer math (the phone derives elapsed/remaining locally from synced params)

    private func makeState(accumulated: Double = 0, timerRunning: Bool = false,
                           startedAtEpoch: Double? = nil, talkLength: Double = 0) -> PresenterState {
        PresenterState(docToken: 1, documentName: "deck.pdf", pageCount: 10, currentIndex: 2,
                       currentLabel: "3", hasNext: true, slideAspect: 16.0 / 9.0, tool: .pen,
                       penColorIndex: 0, blank: .none, magnify: false, preset: .notesRight,
                       splitMode: .auto, isSplit: false, presenting: true, externalDisplays: 1,
                       notesText: "hi", timerRunning: timerRunning, accumulated: accumulated,
                       startedAtEpoch: startedAtEpoch, talkLength: talkLength)
    }

    func testElapsedPausedIsConstant() {
        let s = makeState(accumulated: 120, timerRunning: false)
        XCTAssertEqual(s.elapsed(now: Date(timeIntervalSince1970: 50_000)), 120, accuracy: 0.0001)
        XCTAssertNil(s.remaining(now: Date(timeIntervalSince1970: 50_000)))   // no talk length
    }

    func testElapsedRunningCountsFromResume() {
        let now = Date(timeIntervalSince1970: 1_000)
        let s = makeState(accumulated: 60, timerRunning: true, startedAtEpoch: 990, talkLength: 100)
        XCTAssertEqual(s.elapsed(now: now), 70, accuracy: 0.0001)     // 60 banked + 10 since resume
        XCTAssertEqual(s.remaining(now: now)!, 30, accuracy: 0.0001)
    }

    // MARK: Codable round-trips (the wire format both apps depend on)

    private func assertRoundTrips<T: Codable>(_ value: T, _ label: String,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        do {
            let data = try enc.encode(value)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            XCTAssertEqual(try enc.encode(decoded), data, "round-trip changed \(label)", file: file, line: line)
        } catch {
            XCTFail("round-trip of \(label) threw: \(error)", file: file, line: line)
        }
    }

    func testRemoteCommandRoundTrips() {
        assertRoundTrips(RemoteCommand.next, "next")
        assertRoundTrips(RemoteCommand.goToIndex(5), "goToIndex")
        assertRoundTrips(RemoteCommand.goToLabel("12"), "goToLabel")
        assertRoundTrips(RemoteCommand.setPreset(.notesBottom), "setPreset")
        assertRoundTrips(RemoteCommand.setSplitMode(.splitRight), "setSplitMode")
        assertRoundTrips(RemoteCommand.setTool(.highlighter), "setTool")
        assertRoundTrips(RemoteCommand.setMagnify(true), "setMagnify")
        assertRoundTrips(RemoteCommand.setPenColor(3), "setPenColor")
        assertRoundTrips(RemoteCommand.setTalkLength(1_200), "setTalkLength")
    }

    func testPresenterMessageRoundTrips() {
        assertRoundTrips(PresenterMessage.command(.next), "command")
        assertRoundTrips(PresenterMessage.pointer(CGPoint(x: 0.5, y: 0.25)), "pointer")
        assertRoundTrips(PresenterMessage.pointer(nil), "pointer-lifted")
        assertRoundTrips(PresenterMessage.paired(ok: true, reason: nil), "paired")
        assertRoundTrips(PresenterMessage.state(makeState(accumulated: 42)), "state")
        assertRoundTrips(PresenterMessage.strokeBegin(
            Stroke(points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)],
                   colorIndex: 2, highlighter: true)), "strokeBegin")
    }

    func testPresenterStateDecodesEqual() {
        let s = makeState(accumulated: 42, timerRunning: true, startedAtEpoch: 5, talkLength: 600)
        let back = try! JSONDecoder().decode(PresenterState.self, from: try! JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
    }

    // MARK: Palette index clamping

    func testAnnotationPaletteIndexClamps() {
        XCTAssertEqual(annotationPalette.count, 6)
        XCTAssertEqual(annotationPaletteIndex(-1), 0)
        XCTAssertEqual(annotationPaletteIndex(0), 0)
        XCTAssertEqual(annotationPaletteIndex(5), 5)
        XCTAssertEqual(annotationPaletteIndex(6), 5)     // past the end clamps to last
        XCTAssertEqual(annotationPaletteIndex(100), 5)
    }
}
