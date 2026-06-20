// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import PDFKit
import Observation
import CoreGraphics

enum BlankMode { case none, black, white }
enum Tool: String { case off, laser, pen }
enum SplitMode { case auto, splitRight, single }

/// Presenter-view arrangements. Each lays out the same cards (current / next /
/// notes / status) differently; cards always hug the slide's real aspect ratio.
enum LayoutPreset: String, CaseIterable {
    case notesRight, notesBottom, slideFocus
    var title: String {
        switch self {
        case .notesRight:  return "Notes Right"
        case .notesBottom: return "Notes Bottom"
        case .slideFocus:  return "Slide Focus"
        }
    }
}

/// A freehand annotation stroke. Points are normalized (0...1) inside the slide
/// region, y measured downward (SwiftUI convention) so it maps identically on
/// the presenter panel and the audience screen regardless of their pixel sizes.
struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var width: CGFloat = 0.004   // as a fraction of slide width
}

@Observable
final class PresentationModel {

    // MARK: Document
    var document: PDFDocument?
    var documentURL: URL?
    private(set) var detectedSplit = false

    // MARK: Navigation
    var currentIndex = 0
    var pageCount = 0

    // MARK: Modes
    var splitMode: SplitMode = .auto
    var blank: BlankMode = .none
    var showOverview = false

    // MARK: Tools / annotations
    var tool: Tool = .off
    var pointer: CGPoint? = nil            // normalized laser position in slide region
    var strokes: [Int: [Stroke]] = [:]     // committed strokes, keyed by slide index
    var liveStroke: Stroke? = nil          // stroke currently being drawn

    // MARK: Timer
    var timerRunning = false
    var accumulated: TimeInterval = 0
    var startedAt: Date? = nil

    // MARK: Presenter layout
    var preset: LayoutPreset = .notesRight {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: "presenterPreset") }
    }
    func loadPreset() {
        if let s = UserDefaults.standard.string(forKey: "presenterPreset"),
           let p = LayoutPreset(rawValue: s) { preset = p }
    }
    func cyclePreset() {
        let all = LayoutPreset.allCases
        if let i = all.firstIndex(of: preset) { preset = all[(i + 1) % all.count] }
    }

    // MARK: Split detection / regions

    var isSplit: Bool {
        switch splitMode {
        case .splitRight: return true
        case .single:     return false
        case .auto:       return detectedSplit
        }
    }

    var currentPage: PDFPage? { document?.page(at: currentIndex) }
    var nextIndex: Int? { currentIndex + 1 < pageCount ? currentIndex + 1 : nil }

    /// Aspect (w/h) of the slide half — used to size cards so they hug content.
    var slideAspect: CGFloat {
        guard let p = currentPage else { return 16.0 / 9.0 }
        let r = slideRegion(for: p)
        return r.height > 0 ? r.width / r.height : 16.0 / 9.0
    }
    var notesAspect: CGFloat {
        guard let p = currentPage, let r = notesRegion(for: p), r.height > 0 else { return 16.0 / 9.0 }
        return r.width / r.height
    }

    func load(url: URL) {
        guard let doc = PDFDocument(url: url) else { return }
        document = doc
        documentURL = url
        pageCount = doc.pageCount
        currentIndex = 0
        strokes = [:]
        liveStroke = nil
        pointer = nil
        if let p = doc.page(at: 0) {
            let b = p.bounds(for: .cropBox)
            // Beamer "show notes on second screen" produces double-wide pages.
            detectedSplit = b.height > 0 && (b.width / b.height) > 2.1
        }
    }

    /// The slide half of a page, in 0-based cropBox-local points.
    func slideRegion(for page: PDFPage) -> CGRect {
        let b = page.bounds(for: .cropBox)
        if isSplit { return CGRect(x: 0, y: 0, width: b.width / 2, height: b.height) }
        return CGRect(x: 0, y: 0, width: b.width, height: b.height)
    }

    /// The notes half of a page, or nil when not a split deck.
    func notesRegion(for page: PDFPage) -> CGRect? {
        guard isSplit else { return nil }
        let b = page.bounds(for: .cropBox)
        return CGRect(x: b.width / 2, y: 0, width: b.width / 2, height: b.height)
    }

    // MARK: Navigation
    func goNext()  { if currentIndex + 1 < pageCount { commitStroke(); currentIndex += 1; pointer = nil } }
    func goPrev()  { if currentIndex > 0 { commitStroke(); currentIndex -= 1; pointer = nil } }
    func goFirst() { commitStroke(); currentIndex = 0; pointer = nil }
    func goLast()  { commitStroke(); currentIndex = max(0, pageCount - 1); pointer = nil }
    func goTo(_ i: Int) { if i >= 0 && i < pageCount { commitStroke(); currentIndex = i; pointer = nil } }

    // MARK: Blank
    func toggleBlack() { blank = (blank == .black) ? .none : .black }
    func toggleWhite() { blank = (blank == .white) ? .none : .white }

    // MARK: Timer
    var elapsed: TimeInterval {
        accumulated + (timerRunning ? (startedAt.map { -$0.timeIntervalSinceNow } ?? 0) : 0)
    }
    func toggleTimer() {
        if timerRunning {
            accumulated = elapsed
            timerRunning = false
            startedAt = nil
        } else {
            startedAt = Date()
            timerRunning = true
        }
    }
    func resetTimer() {
        accumulated = 0
        startedAt = timerRunning ? Date() : nil
    }
    func startTimerIfNeeded() {
        if !timerRunning && accumulated == 0 { toggleTimer() }
    }

    // MARK: Annotations
    func commitStroke() {
        if let s = liveStroke, s.points.count > 1 {
            strokes[currentIndex, default: []].append(s)
        }
        liveStroke = nil
    }
    func clearAnnotations() {
        strokes[currentIndex] = []
        liveStroke = nil
        pointer = nil
    }
}
