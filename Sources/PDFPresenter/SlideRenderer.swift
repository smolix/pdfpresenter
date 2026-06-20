// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import AppKit
import PDFKit

/// Renders cropped PDF page regions to NSImages and caches them. All PDFKit
/// drawing is funnelled through a single serial queue so the document is never
/// touched from two threads at once.
final class SlideRenderer {
    static let shared = SlideRenderer()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "org.smola.pdfpresenter.render", qos: .userInitiated)

    init() { cache.countLimit = 256 }

    /// Returns a rendered image, rendering synchronously on a cache miss.
    func image(page: PDFPage, region: CGRect, key: String, pixelWidth: CGFloat) -> NSImage {
        if let img = cache.object(forKey: key as NSString) { return img }
        let img = queue.sync { Self.render(page: page, region: region, pixelWidth: pixelWidth) }
        cache.setObject(img, forKey: key as NSString)
        return img
    }

    /// Warms the cache off the main thread (best effort).
    func prefetch(page: PDFPage, region: CGRect, key: String, pixelWidth: CGFloat) {
        if cache.object(forKey: key as NSString) != nil { return }
        queue.async { [weak self] in
            guard let self else { return }
            if self.cache.object(forKey: key as NSString) != nil { return }
            let img = Self.render(page: page, region: region, pixelWidth: pixelWidth)
            self.cache.setObject(img, forKey: key as NSString)
        }
    }

    private static func render(page: PDFPage, region: CGRect, pixelWidth: CGFloat) -> NSImage {
        let pw = max(16, pixelWidth)
        let scale = pw / region.width
        let pxW = max(1, Int(pw.rounded()))
        let pxH = max(1, Int((region.height * scale).rounded()))

        // Raw CGContext sized in PIXELS, then an explicit points->pixels scale.
        // This is fully self-contained: no NSGraphicsContext, no rep.size timing,
        // and no mutation of the global current context — so it renders the same
        // whether called standalone or inside SwiftUI's ImageRenderer.
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return NSImage(size: region.size)
        }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        ctx.scaleBy(x: scale, y: scale)               // map page points -> pixels
        ctx.translateBy(x: -region.minX, y: -region.minY)
        page.draw(with: .cropBox, to: ctx)            // content outside the region is clipped by bounds

        guard let cg = ctx.makeImage() else { return NSImage(size: region.size) }
        return NSImage(cgImage: cg, size: region.size)
    }
}
