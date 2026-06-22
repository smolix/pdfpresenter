// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import CoreGraphics

// Pure deck logic shared by the macOS app and the iOS companion, factored out of
// the view models so it can be unit-tested without a window, a simulator, or a
// real PDF on disk. Everything here is a value-in / value-out function.

// MARK: - Notes-split detection

/// Past this cropBox aspect (w/h) a page is auto-detected as a Beamer
/// "show notes on second screen" deck: slide on the left half, notes on the right.
public let notesSplitAspect: CGFloat = 2.1
/// A page must be at least this wide before a *forced* split is allowed, so
/// "force split" can't cut a normal 4:3 / 16:9 page down the middle.
public let wideEnoughToSplitAspect: CGFloat = 1.9

/// How a page's geometry classifies for notes-splitting.
public struct SplitDetection: Equatable, Sendable {
    public var detectedSplit: Bool   // wide enough to auto-detect as a notes deck
    public var pageIsWide: Bool      // wide enough to permit a forced split at all
    public init(detectedSplit: Bool, pageIsWide: Bool) {
        self.detectedSplit = detectedSplit
        self.pageIsWide = pageIsWide
    }
}

/// Classify a page from its cropBox aspect (w/h). A non-positive aspect (an empty
/// or unreadable page) classifies as not-split.
public func detectSplit(cropBoxAspect aspect: CGFloat) -> SplitDetection {
    SplitDetection(detectedSplit: aspect > notesSplitAspect,
                   pageIsWide: aspect > wideEnoughToSplitAspect)
}

/// Whether only the slide half should be shown, given the user's mode and the
/// page classification. `.splitRight` forces a split but only on an actually-wide
/// page; `.single` never splits; `.auto` follows detection.
public func isSplitActive(mode: SplitMode, detection: SplitDetection) -> Bool {
    switch mode {
    case .splitRight: return detection.pageIsWide
    case .single:     return false
    case .auto:       return detection.detectedSplit
    }
}

/// The slide half of a page, in cropBox-local points (the full page when not
/// split).
public func slideRegion(cropBox: CGSize, split: Bool) -> CGRect {
    split ? CGRect(x: 0, y: 0, width: cropBox.width / 2, height: cropBox.height)
          : CGRect(x: 0, y: 0, width: cropBox.width, height: cropBox.height)
}

/// The notes half of a page, in cropBox-local points, or nil when not split.
public func notesRegion(cropBox: CGSize, split: Bool) -> CGRect? {
    guard split else { return nil }
    return CGRect(x: cropBox.width / 2, y: 0, width: cropBox.width / 2, height: cropBox.height)
}

// MARK: - Page-label lookup

/// Resolve a typed page number against the document's own page labels (the
/// numbers printed on the slides). Returns the first index whose label equals the
/// trimmed query, or nil when none match (so the caller can fall back / beep).
public func resolveSlideLabel(_ query: String, in labels: [String]) -> Int? {
    let target = query.trimmingCharacters(in: .whitespaces)
    guard !target.isEmpty else { return nil }
    return labels.firstIndex(of: target)
}

// MARK: - Notes sidecar parsing

/// Parse speaker notes keyed by slide number. A line like `# 3`, `## 3`, or
/// `# Slide 3` starts the notes for that slide; following lines are its body
/// (trimmed). Lines before the first header are ignored.
public func parseSlideNotes(_ text: String) -> [Int: String] {
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

private func slideHeaderNumber(_ line: String) -> Int? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("#") else { return nil }
    var body = t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
    if body.hasPrefix("slide") { body = String(body.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
    let digits = body.prefix(while: { $0.isNumber })
    return digits.isEmpty ? nil : Int(digits)
}
