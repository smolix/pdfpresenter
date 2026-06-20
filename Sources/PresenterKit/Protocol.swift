// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import CoreGraphics

/// The Multipeer service type both apps advertise/browse. Must be ≤15 chars,
/// lowercase letters / digits / hyphens.
public let presenterServiceType = "pdfpres-ctl"

/// Which region of a page a thumbnail depicts.
public enum SlideKind: String, Codable, Sendable { case slide, notes }

/// A snapshot of the macOS presenter the iOS companion mirrors. Equatable so the
/// Mac only re-sends it when something actually changed. The timer is sent as
/// its parameters (not a live tick) so the phone can run its own clock.
public struct PresenterState: Codable, Equatable, Sendable {
    public var docToken: Int
    public var documentName: String
    public var pageCount: Int
    public var currentIndex: Int
    public var currentLabel: String
    public var hasNext: Bool
    public var slideAspect: Double

    public var tool: Tool
    public var penColorIndex: Int
    public var blank: BlankMode
    public var magnify: Bool

    public var preset: LayoutPreset
    public var splitMode: SplitMode
    public var isSplit: Bool
    public var presenting: Bool         // audience cover currently shown
    public var externalDisplays: Int    // non-presenter screens available

    public var notesText: String?

    public var timerRunning: Bool
    public var accumulated: Double       // seconds banked at last pause
    public var startedAtEpoch: Double?   // when running, timeIntervalSince1970 of resume
    public var talkLength: Double        // 0 = count up only

    public init(docToken: Int, documentName: String, pageCount: Int, currentIndex: Int,
                currentLabel: String, hasNext: Bool, slideAspect: Double, tool: Tool,
                penColorIndex: Int, blank: BlankMode, magnify: Bool, preset: LayoutPreset,
                splitMode: SplitMode, isSplit: Bool, presenting: Bool, externalDisplays: Int,
                notesText: String?, timerRunning: Bool, accumulated: Double,
                startedAtEpoch: Double?, talkLength: Double) {
        self.docToken = docToken; self.documentName = documentName; self.pageCount = pageCount
        self.currentIndex = currentIndex; self.currentLabel = currentLabel; self.hasNext = hasNext
        self.slideAspect = slideAspect; self.tool = tool; self.penColorIndex = penColorIndex
        self.blank = blank; self.magnify = magnify; self.preset = preset; self.splitMode = splitMode
        self.isSplit = isSplit; self.presenting = presenting; self.externalDisplays = externalDisplays
        self.notesText = notesText; self.timerRunning = timerRunning; self.accumulated = accumulated
        self.startedAtEpoch = startedAtEpoch; self.talkLength = talkLength
    }

    /// Elapsed seconds computed locally from the synced timer parameters.
    public func elapsed(now: Date = Date()) -> TimeInterval {
        accumulated + (timerRunning ? (startedAtEpoch.map { now.timeIntervalSince1970 - $0 } ?? 0) : 0)
    }
    public func remaining(now: Date = Date()) -> TimeInterval? {
        talkLength > 0 ? talkLength - elapsed(now: now) : nil
    }
}

/// A control action the companion asks the Mac to perform. Mirrors the desktop
/// presenter's keyboard / toolbar actions.
public enum RemoteCommand: Codable, Sendable {
    case next, prev, first, last
    case goToIndex(Int)
    case goToLabel(String)
    case toggleBlack, toggleWhite
    case toggleTimer, resetTimer
    case cyclePreset
    case setPreset(LayoutPreset)
    case setSplitMode(SplitMode)
    case toggleFullscreen, cycleDisplay
    case setTool(Tool)
    case clearAnnotations
    case setMagnify(Bool)
    case setPenColor(Int)
    case setTalkLength(Double)
}

/// One framed message in either direction over the peer link.
public enum PresenterMessage: Codable, Sendable {
    // iOS → Mac
    case pair(code: String, device: String)   // present the code shown on the Mac
    case command(RemoteCommand)
    case pointer(CGPoint?)                     // laser/spotlight/zoom focus; nil = lifted
    case strokeBegin(Stroke)
    case strokeExtend(CGPoint)
    case strokeEnd
    case erase(CGPoint)
    case requestThumbnails                     // (re)send current + next images & strokes

    // Mac → iOS
    case paired(ok: Bool, reason: String?)
    case state(PresenterState)
    case thumbnail(index: Int, kind: SlideKind, jpeg: Data, aspect: Double, token: Int)
    case strokes(index: Int, strokes: [Stroke])
}
