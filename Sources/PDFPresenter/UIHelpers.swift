// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI

enum RegionKind { case slide, notes }

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
