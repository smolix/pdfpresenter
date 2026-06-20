// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import AppKit
import PresenterKit

enum RegionKind { case slide, notes }

/// Annotation pen palette (toolbar swatches, on-screen drawing, PDF export),
/// derived from PresenterKit's shared palette so it matches the iOS companion.
let annotationNSColors: [NSColor] = annotationPalette.map {
    NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1)
}
func annotationColorIndex(_ i: Int) -> Int { annotationPaletteIndex(i) }
func annotationColor(_ i: Int) -> Color { Color(nsColor: annotationNSColors[annotationColorIndex(i)]) }

// fittedRect / fittedSize / clamp / elapsedString / clockString live in PresenterKit.
