// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import AppKit

enum RegionKind { case slide, notes }

/// Annotation pen palette, shared by the toolbar swatches, the on-screen
/// drawing, and the annotated-PDF export.
let annotationNSColors: [NSColor] = [
    NSColor(srgbRed: 0.93, green: 0.23, blue: 0.21, alpha: 1),  // red
    NSColor(srgbRed: 0.20, green: 0.50, blue: 0.96, alpha: 1),  // blue
    NSColor(srgbRed: 0.17, green: 0.70, blue: 0.36, alpha: 1),  // green
    NSColor(srgbRed: 0.98, green: 0.78, blue: 0.12, alpha: 1),  // yellow
    NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1),  // white
    NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1),  // black
]
func annotationColorIndex(_ i: Int) -> Int { max(0, min(i, annotationNSColors.count - 1)) }
func annotationColor(_ i: Int) -> Color { Color(nsColor: annotationNSColors[annotationColorIndex(i)]) }

/// The largest rect of the given aspect (w/h) that fits centered inside `size`.
func fittedRect(aspect: CGFloat, in size: CGSize) -> CGRect {
    guard aspect > 0, size.width > 0, size.height > 0 else {
        return CGRect(origin: .zero, size: size)
    }
    let containerAspect = size.width / size.height
    var w = size.width
    var h = size.height
    if aspect > containerAspect { h = w / aspect } else { w = h * aspect }
    return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
}

/// The largest size of the given aspect (w/h) that fits inside `size`.
func fittedSize(aspect: CGFloat, in size: CGSize) -> CGSize {
    guard aspect > 0, size.width > 0, size.height > 0 else { return size }
    let containerAspect = size.width / size.height
    if aspect > containerAspect {
        return CGSize(width: size.width, height: size.width / aspect)
    } else {
        return CGSize(width: size.height * aspect, height: size.height)
    }
}

func clamp(_ v: CGFloat, _ lo: CGFloat = 0, _ hi: CGFloat = 1) -> CGFloat {
    min(max(v, lo), hi)
}

private let clockFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

func clockString() -> String { clockFormatter.string(from: Date()) }

func elapsedString(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}
