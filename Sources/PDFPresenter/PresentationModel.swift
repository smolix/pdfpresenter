// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import PDFKit
import Observation
import CoreGraphics
import PresenterKit

// BlankMode, Tool, SplitMode, LayoutPreset and Stroke live in PresenterKit so
// the iOS companion shares them verbatim.

@Observable
final class PresentationModel {

    // MARK: Document
    var document: PDFDocument?
    var documentURL: URL?
    private(set) var detectedSplit = false
    private(set) var pageIsWide = false  // page 0 wide enough to be a notes split at all (~1.9:1+)
    private(set) var docToken = 0       // bumps each load() so render-cache keys can't collide across decks

    // MARK: Navigation
    var currentIndex = 0
    var pageCount = 0

    // MARK: Modes
    var splitMode: SplitMode = .auto
    var blank: BlankMode = .none
    var showOverview = false
    var showHelp = false

    // MARK: Tools / annotations
    var tool: Tool = .off
    var penColorIndex = 0
    var pointer: CGPoint? = nil            // normalized cursor over the current slide
    var magnify = false                    // zoom-into-pointer toggle
    var strokes: [Int: [Stroke]] = [:]     // committed strokes, keyed by slide index
    var liveStroke: Stroke? = nil          // stroke currently being drawn

    // MARK: Timer
    var timerRunning = false
    var accumulated: TimeInterval = 0
    var startedAt: Date? = nil
    var talkLength: TimeInterval = 0 {     // 0 = count up only; >0 = count down
        didSet { UserDefaults.standard.set(talkLength, forKey: "talkLength") }
    }

    // MARK: Speaker notes (sidecar, for non-split decks)
    var notesSidecar: [Int: String] = [:]  // 1-based slide number -> notes text

    // MARK: Presenter layout
    var preset: LayoutPreset = .notesRight {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: "presenterPreset") }
    }

    func loadSettings() {
        if let s = UserDefaults.standard.string(forKey: "presenterPreset"),
           let p = LayoutPreset(rawValue: s) { preset = p }
        let t = UserDefaults.standard.double(forKey: "talkLength")
        if t > 0 { talkLength = t }
    }
    func cyclePreset() {
        let all = LayoutPreset.allCases
        if let i = all.firstIndex(of: preset) { preset = all[(i + 1) % all.count] }
    }

    // MARK: Split detection / regions

    var isSplit: Bool {
        switch splitMode {
        case .splitRight: return pageIsWide   // force split, but only on an actually-wide page
        case .single:     return false
        case .auto:       return detectedSplit
        }
    }

    var currentPage: PDFPage? { document?.page(at: currentIndex) }
    var nextIndex: Int? { currentIndex + 1 < pageCount ? currentIndex + 1 : nil }

    // MARK: Page labels (the document's own page numbers, e.g. printed on slides)

    /// The document's label for a page (skips the title, restarts numbering,
    /// repeats across overlay frames, …), falling back to the 1-based index when
    /// the PDF carries no page labels.
    func label(for index: Int) -> String {
        guard index >= 0, index < pageCount, let l = document?.page(at: index)?.label,
              !l.isEmpty else { return index >= 0 ? "\(index + 1)" : "" }
        return l
    }
    var currentLabel: String { pageCount == 0 ? "0" : label(for: currentIndex) }
    /// True when the PDF defines its own page numbering that differs from the
    /// raw 1-based order (so jump-by-number should resolve against labels).
    var hasCustomLabels: Bool {
        guard let doc = document else { return false }
        for i in 0..<pageCount where doc.page(at: i)?.label.map({ $0 != "\(i + 1)" }) == true {
            return true
        }
        return false
    }

    /// Jump to the page whose document label matches `text`. Returns false when
    /// no page carries that label (caller can beep). Used by type-a-number-then-
    /// Return so the typed number is the document's page number, not the index.
    @discardableResult
    func goToLabel(_ text: String) -> Bool {
        let target = text.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return false }
        if let idx = (0..<pageCount).first(where: { label(for: $0) == target }) {
            goTo(idx); return true
        }
        return false
    }

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

    /// Sidecar notes for the current slide (nil when none / empty).
    var currentNotesText: String? {
        let t = notesSidecar[currentIndex + 1]
        return (t?.isEmpty == false) ? t : nil
    }
    var hasSidecarNotes: Bool { !notesSidecar.isEmpty }

    func load(url: URL) {
        guard let doc = PDFDocument(url: url) else { return }
        document = doc
        documentURL = url
        pageCount = doc.pageCount
        currentIndex = 0
        docToken += 1
        SlideRenderer.shared.clear()
        liveStroke = nil
        pointer = nil
        if let p = doc.page(at: 0) {
            let b = p.bounds(for: .cropBox)
            let aspect = b.height > 0 ? b.width / b.height : 0
            // Beamer "show notes on second screen" produces double-wide pages.
            detectedSplit = aspect > 2.1   // auto-detect a notes deck
            pageIsWide = aspect > 1.9      // wide enough to split at all (guards forced split)
        }
        loadAnnotations()
        loadNotesSidecar()
    }

    /// Re-reads the current document from disk (e.g. after a LaTeX rebuild)
    /// without losing the presenter's place or annotations. Keeps the page
    /// identified by its document label when that label survives the rebuild,
    /// else clamps the old index into the new page count. Returns false if the
    /// file can't be read yet (so a caller can leave the old deck in place).
    @discardableResult
    func reload() -> Bool {
        guard let url = documentURL, let doc = PDFDocument(url: url), doc.pageCount > 0 else { return false }
        let oldLabel = currentLabel
        let oldIndex = currentIndex
        document = doc
        pageCount = doc.pageCount
        docToken += 1
        SlideRenderer.shared.clear()
        liveStroke = nil
        pointer = nil
        if let p = doc.page(at: 0) {
            let b = p.bounds(for: .cropBox)
            let aspect = b.height > 0 ? b.width / b.height : 0
            detectedSplit = aspect > 2.1
            pageIsWide = aspect > 1.9
        }
        if let idx = (0..<pageCount).first(where: { label(for: $0) == oldLabel }) {
            currentIndex = idx
        } else {
            currentIndex = min(max(0, oldIndex), pageCount - 1)
        }
        loadNotesSidecar()   // notes may have been edited alongside the deck
        return true          // annotations (keyed by index) are kept as-is
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
    /// Time remaining against the talk-length target, or nil when no target set.
    var remaining: TimeInterval? { talkLength > 0 ? talkLength - elapsed : nil }
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
    func beginStroke(at p: CGPoint) {
        liveStroke = Stroke(points: [p],
                            width: tool == .highlighter ? 0.022 : 0.005,
                            colorIndex: penColorIndex,
                            highlighter: tool == .highlighter)
    }
    func extendStroke(to p: CGPoint) { liveStroke?.points.append(p) }
    func commitStroke() {
        if let s = liveStroke, s.points.count > 1 {
            strokes[currentIndex, default: []].append(s)
            saveAnnotations()
        }
        liveStroke = nil
    }
    func eraseAt(_ p: CGPoint, radius: CGFloat = 0.03) {
        guard var arr = strokes[currentIndex], !arr.isEmpty else { return }
        let before = arr.count
        arr.removeAll { s in s.points.contains { hypot($0.x - p.x, $0.y - p.y) <= radius } }
        if arr.count != before { strokes[currentIndex] = arr; saveAnnotations() }
    }
    func clearAnnotations() {
        strokes[currentIndex] = []
        liveStroke = nil
        pointer = nil
        saveAnnotations()
    }
    var hasAnnotations: Bool { strokes.values.contains { !$0.isEmpty } }

    // MARK: Annotation persistence (sidecar JSON next to the PDF)
    private var annotationsURL: URL? {
        documentURL?.deletingPathExtension().appendingPathExtension("pdfpres.json")
    }
    func saveAnnotations() {
        guard let url = annotationsURL else { return }
        let dict = Dictionary(uniqueKeysWithValues: strokes.map { (String($0.key), $0.value) })
        if dict.values.allSatisfy({ $0.isEmpty }) {
            try? FileManager.default.removeItem(at: url)   // nothing to keep
            return
        }
        if let data = try? JSONEncoder().encode(dict) { try? data.write(to: url) }
    }
    private func loadAnnotations() {
        strokes = [:]
        guard let url = annotationsURL, let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [Stroke]].self, from: data) else { return }
        var s: [Int: [Stroke]] = [:]
        for (k, v) in dict { if let i = Int(k) { s[i] = v } }
        strokes = s
    }

    // MARK: Notes sidecar parsing
    private func loadNotesSidecar() {
        notesSidecar = [:]
        guard let url = documentURL else { return }
        let base = url.deletingPathExtension()
        for ext in ["md", "markdown", "txt", "notes"] {
            let candidate = base.appendingPathExtension(ext)
            if let text = try? String(contentsOf: candidate, encoding: .utf8) {
                notesSidecar = Self.parseNotes(text)
                break
            }
        }
    }

    /// Parses notes keyed by slide number. A line like `# 3`, `## 3`, or
    /// `# Slide 3` starts the notes for that slide; following lines are its body.
    static func parseNotes(_ text: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var current: Int? = nil
        var buffer: [String] = []
        func flush() {
            if let c = current {
                result[c] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            buffer = []
        }
        for line in text.components(separatedBy: .newlines) {
            if let n = slideHeaderNumber(line) { flush(); current = n }
            else { buffer.append(line) }
        }
        flush()
        return result
    }
    private static func slideHeaderNumber(_ line: String) -> Int? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return nil }
        var body = t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
        if body.hasPrefix("slide") { body = String(body.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        let digits = body.prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : Int(digits)
    }
}
