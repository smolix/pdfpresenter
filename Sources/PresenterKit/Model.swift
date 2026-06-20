// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import CoreGraphics

// Core presentation value types, shared verbatim by the macOS app and the iOS
// companion so a stroke drawn on the iPad lands pixel-identically on the
// audience screen and a tool chosen on either side means the same thing.

public enum BlankMode: String, Codable, Sendable { case none, black, white }

public enum Tool: String, Codable, CaseIterable, Sendable {
    case off, laser, pen, highlighter, eraser, spotlight
}

public enum SplitMode: String, Codable, Sendable { case auto, splitRight, single }

/// Presenter-view arrangements. Each lays out the same cards (current / next /
/// notes / status) differently; cards always hug the slide's real aspect ratio.
public enum LayoutPreset: String, Codable, CaseIterable, Sendable {
    case notesRight, notesBottom, slideFocus
    public var title: String {
        switch self {
        case .notesRight:  return "Notes Right"
        case .notesBottom: return "Notes Bottom"
        case .slideFocus:  return "Slide Focus"
        }
    }
}

/// A freehand annotation stroke. Points are normalized (0...1) inside the slide
/// region, y measured downward (SwiftUI convention) so it maps identically on
/// the presenter panel, the audience screen, and the iPad regardless of pixels.
public struct Stroke: Identifiable, Codable, Sendable {
    public var id: UUID
    public var points: [CGPoint]
    public var width: CGFloat        // fraction of slide width
    public var colorIndex: Int       // index into the annotation palette
    public var highlighter: Bool

    public init(id: UUID = UUID(), points: [CGPoint], width: CGFloat = 0.005,
                colorIndex: Int = 0, highlighter: Bool = false) {
        self.id = id
        self.points = points
        self.width = width
        self.colorIndex = colorIndex
        self.highlighter = highlighter
    }
}

/// The annotation pen palette as raw sRGB, so every platform derives the exact
/// same colors (macOS NSColor, iOS UIColor/SwiftUI Color, PDF export).
public struct PaletteColor: Sendable { public let r, g, b: Double }

public let annotationPalette: [PaletteColor] = [
    PaletteColor(r: 0.93, g: 0.23, b: 0.21),  // red
    PaletteColor(r: 0.20, g: 0.50, b: 0.96),  // blue
    PaletteColor(r: 0.17, g: 0.70, b: 0.36),  // green
    PaletteColor(r: 0.98, g: 0.78, b: 0.12),  // yellow
    PaletteColor(r: 0.96, g: 0.96, b: 0.97),  // white
    PaletteColor(r: 0.10, g: 0.10, b: 0.12),  // black
]

public func annotationPaletteIndex(_ i: Int) -> Int {
    max(0, min(i, annotationPalette.count - 1))
}
