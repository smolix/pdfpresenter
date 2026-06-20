// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

// Generates a Beamer-style "notes on second screen" test deck: double-wide
// pages with the slide on the left half and notes on the right half.
//
//   swift tools/make_test_pdf.swift [out.pdf] [pageCount]
//
import AppKit

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "test-split.pdf"
let pages = args.count > 2 ? (Int(args[2]) ?? 12) : 12

let slideW: CGFloat = 1280
let slideH: CGFloat = 720
let pageRect = CGRect(x: 0, y: 0, width: slideW * 2, height: slideH)

var mediaBox = pageRect
let url = URL(fileURLWithPath: outPath)
guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
    FileHandle.standardError.write(Data("Failed to create PDF context\n".utf8)); exit(1)
}

func attr(_ s: String, _ size: CGFloat, _ color: NSColor, bold: Bool = false,
          align: NSTextAlignment = .left) -> NSAttributedString {
    let para = NSMutableParagraphStyle(); para.lineSpacing = 10; para.alignment = align
    let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    return NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: para
    ])
}

for i in 1...pages {
    ctx.beginPDFPage(nil)
    ctx.saveGState()
    // Flip to a top-left origin so text and rects share one intuitive coord system.
    ctx.translateBy(x: 0, y: pageRect.height)
    ctx.scaleBy(x: 1, y: -1)
    let g = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g

    let hue = CGFloat((i - 1)) / CGFloat(max(1, pages))

    // Slide (left half)
    NSColor(calibratedHue: hue, saturation: 0.16, brightness: 0.99, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: slideW, height: slideH).fill()
    // Notes (right half)
    NSColor(white: 0.96, alpha: 1).setFill()
    NSRect(x: slideW, y: 0, width: slideW, height: slideH).fill()
    // Divider
    NSColor(white: 0.72, alpha: 1).setFill()
    NSRect(x: slideW - 1, y: 0, width: 2, height: slideH).fill()
    // Footer accent on the slide (bottom in top-left coords)
    NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.72, alpha: 1).setFill()
    NSRect(x: 0, y: slideH - 16, width: slideW, height: 16).fill()

    // Slide title
    let title = attr("Slide \(i)", 130, NSColor(white: 0.14, alpha: 1), bold: true)
    let ts = title.size()
    title.draw(at: NSPoint(x: (slideW - ts.width) / 2, y: slideH * 0.30))
    let sub = attr("of \(pages)", 46, NSColor(white: 0.42, alpha: 1))
    let ss = sub.size()
    sub.draw(at: NSPoint(x: (slideW - ss.width) / 2, y: slideH * 0.30 + ts.height + 16))

    // Notes block
    let notes = """
    Notes — slide \(i)

    • Talking point one for this slide
    • Emphasize the key idea
    • Mention the running example
    • Transition to slide \(min(i + 1, pages))
    """
    attr(notes, 36, NSColor(white: 0.2, alpha: 1))
        .draw(in: NSRect(x: slideW + 70, y: 90, width: slideW - 140, height: slideH - 180))

    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
    ctx.endPDFPage()
}
ctx.closePDF()
print("Wrote \(pages)-page split deck → \(outPath)")
