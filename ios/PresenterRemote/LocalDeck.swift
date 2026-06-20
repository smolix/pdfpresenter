// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import SwiftUI
import UIKit
import PDFKit
import PresenterKit

/// A presentation driven entirely on this device (no Mac) — the iPad/iPhone
/// opens a PDF and shows the presenter view locally, with the audience slide on
/// a connected external display. Mirrors the macOS `PresentationModel`: same
/// split detection, page labels, regions, strokes, tools, and timer.
@MainActor @Observable
final class LocalDeck {

    private(set) var document: PDFDocument?
    private(set) var documentName = ""
    private(set) var pageCount = 0
    private(set) var detectedSplit = false
    private(set) var pageIsWide = false
    private(set) var docToken = 0

    var currentIndex = 0
    var splitMode: SplitMode = .auto
    var blank: BlankMode = .none
    var tool: Tool = .off
    var penColorIndex = 0
    var magnify = false
    var pointer: CGPoint?
    var strokes: [Int: [Stroke]] = [:]
    var liveStroke: Stroke?

    var timerRunning = false
    var accumulated: TimeInterval = 0
    var startedAt: Date?
    var talkLength: TimeInterval = 0

    private let renderer = LocalSlideRenderer()

    // MARK: Load

    func load(url: URL) {
        // Picked files are security-scoped; keep access open while presenting.
        let scoped = url.startAccessingSecurityScopedResource()
        guard let doc = PDFDocument(url: url) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return
        }
        document = doc
        documentName = url.lastPathComponent
        pageCount = doc.pageCount
        currentIndex = 0
        docToken += 1
        strokes = [:]; liveStroke = nil; pointer = nil
        renderer.clear()
        if let p = doc.page(at: 0) {
            let b = p.bounds(for: .cropBox)
            let aspect = b.height > 0 ? b.width / b.height : 0
            detectedSplit = aspect > 2.1
            pageIsWide = aspect > 1.9
        }
    }

    // MARK: Split / regions (identical rules to the Mac)

    var isSplit: Bool {
        switch splitMode {
        case .splitRight: return pageIsWide
        case .single:     return false
        case .auto:       return detectedSplit
        }
    }
    var currentPage: PDFPage? { document?.page(at: currentIndex) }
    var nextIndex: Int? { currentIndex + 1 < pageCount ? currentIndex + 1 : nil }

    func slideRegion(for page: PDFPage) -> CGRect {
        let b = page.bounds(for: .cropBox)
        return isSplit ? CGRect(x: 0, y: 0, width: b.width / 2, height: b.height)
                       : CGRect(x: 0, y: 0, width: b.width, height: b.height)
    }
    func notesRegion(for page: PDFPage) -> CGRect? {
        guard isSplit else { return nil }
        let b = page.bounds(for: .cropBox)
        return CGRect(x: b.width / 2, y: 0, width: b.width / 2, height: b.height)
    }
    var slideAspect: CGFloat {
        guard let p = currentPage else { return 16.0 / 9.0 }
        let r = slideRegion(for: p)
        return r.height > 0 ? r.width / r.height : 16.0 / 9.0
    }
    var notesAspect: CGFloat {
        guard let p = currentPage, let r = notesRegion(for: p), r.height > 0 else { return 16.0 / 9.0 }
        return r.width / r.height
    }

    // MARK: Rendering

    func image(index: Int, kind: RegionKind, pixelWidth: CGFloat) -> UIImage? {
        guard let doc = document, index >= 0, index < pageCount, let page = doc.page(at: index) else { return nil }
        let region: CGRect
        switch kind {
        case .slide: region = slideRegion(for: page)
        case .notes: guard let n = notesRegion(for: page) else { return nil }; region = n
        }
        guard region.width > 0, region.height > 0 else { return nil }
        let bucket = max(64, (pixelWidth / 128).rounded() * 128)
        let key = "\(docToken)|\(index)|\(kind)|\(isSplit)|\(Int(bucket))"
        return renderer.image(page: page, region: region, key: key, pixelWidth: bucket)
    }

    // MARK: Page labels

    func label(for index: Int) -> String {
        guard index >= 0, index < pageCount, let l = document?.page(at: index)?.label, !l.isEmpty
        else { return index >= 0 ? "\(index + 1)" : "" }
        return l
    }
    var currentLabel: String { pageCount == 0 ? "0" : label(for: currentIndex) }
    @discardableResult func goToLabel(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if let i = (0..<pageCount).first(where: { label(for: $0) == t }) { goTo(i); return true }
        if let n = Int(t), n >= 1, n <= pageCount { goTo(n - 1); return true }
        return false
    }

    // MARK: Navigation
    func goNext()  { if currentIndex + 1 < pageCount { commitStroke(); currentIndex += 1; pointer = nil } }
    func goPrev()  { if currentIndex > 0 { commitStroke(); currentIndex -= 1; pointer = nil } }
    func goFirst() { commitStroke(); currentIndex = 0; pointer = nil }
    func goLast()  { commitStroke(); currentIndex = max(0, pageCount - 1); pointer = nil }
    func goTo(_ i: Int) { if i >= 0, i < pageCount { commitStroke(); currentIndex = i; pointer = nil } }

    func toggleBlack() { blank = (blank == .black) ? .none : .black }
    func toggleWhite() { blank = (blank == .white) ? .none : .white }

    // MARK: Timer
    var elapsed: TimeInterval { accumulated + (timerRunning ? (startedAt.map { -$0.timeIntervalSinceNow } ?? 0) : 0) }
    var remaining: TimeInterval? { talkLength > 0 ? talkLength - elapsed : nil }
    func toggleTimer() {
        if timerRunning { accumulated = elapsed; timerRunning = false; startedAt = nil }
        else { startedAt = Date(); timerRunning = true }
    }
    func resetTimer() { accumulated = 0; startedAt = timerRunning ? Date() : nil }
    func startTimerIfNeeded() { if !timerRunning && accumulated == 0 { toggleTimer() } }
    func advance() { startTimerIfNeeded(); goNext() }

    // MARK: Annotations
    func beginStroke(_ s: Stroke) { liveStroke = s }
    func extendStroke(_ p: CGPoint) { liveStroke?.points.append(p) }
    func commitStroke() {
        if let s = liveStroke, s.points.count > 1 { strokes[currentIndex, default: []].append(s) }
        liveStroke = nil
    }
    func eraseAt(_ p: CGPoint, radius: CGFloat = 0.03) {
        guard var arr = strokes[currentIndex], !arr.isEmpty else { return }
        arr.removeAll { s in s.points.contains { hypot($0.x - p.x, $0.y - p.y) <= radius } }
        strokes[currentIndex] = arr
    }
    func clearAnnotations() { strokes[currentIndex] = []; liveStroke = nil; pointer = nil }
    func cyclePenColor() { penColorIndex = (penColorIndex + 1) % annotationPalette.count }

    #if DEBUG
    /// Generates a 6-page PDF and loads it — for offline UI checks (`-localdemo`)
    /// without needing a file in the Simulator's Files.
    func loadDemo() {
        let size = CGSize(width: 1280, height: 720)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("localdemo.pdf")
        let r = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        try? r.writePDF(to: url) { ctx in
            for i in 1...6 {
                ctx.beginPage()
                UIColor(hue: CGFloat(i - 1) / 6, saturation: 0.16, brightness: 0.99, alpha: 1).setFill()
                ctx.cgContext.fill(CGRect(origin: .zero, size: size))
                ("Local Slide \(i)" as NSString).draw(at: CGPoint(x: 120, y: 250), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 120),
                    .foregroundColor: UIColor(white: 0.14, alpha: 1)])
            }
        }
        load(url: url)
    }
    #endif
}

/// Renders cropped PDF regions to UIImage via a raw CGContext (y-up, identical
/// to the macOS renderer), with an NSCache. PDFKit drawing stays on the main
/// actor; results cache after the first navigation to a slide.
@MainActor
final class LocalSlideRenderer {
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.countLimit = 256 }
    func clear() { cache.removeAllObjects() }

    func image(page: PDFPage, region: CGRect, key: String, pixelWidth: CGFloat) -> UIImage {
        if let img = cache.object(forKey: key as NSString) { return img }
        let img = Self.render(page: page, region: region, pixelWidth: pixelWidth)
        cache.setObject(img, forKey: key as NSString)
        return img
    }

    private static func render(page: PDFPage, region: CGRect, pixelWidth: CGFloat) -> UIImage {
        let pw = max(16, pixelWidth)
        let scale = pw / region.width
        let pxW = max(1, Int(pw.rounded()))
        let pxH = max(1, Int((region.height * scale).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return UIImage() }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        page.draw(with: .cropBox, to: ctx)
        guard let cg = ctx.makeImage() else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}

enum RegionKind { case slide, notes }
