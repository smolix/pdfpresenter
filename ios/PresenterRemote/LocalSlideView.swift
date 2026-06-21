// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import PresenterKit

/// One slide of a locally-opened deck: the rendered region, committed + live
/// ink, laser/spotlight, and the magnifier — driven by a `LocalDeck` instead of
/// the network. Interactive slides take Apple Pencil / touch (draw, erase,
/// point) and swipe-to-navigate in cursor mode.
struct LocalSlideView: View {
    @Bindable var deck: LocalDeck
    var interactive: Bool

    var body: some View {
        GeometryReader { geo in
            let idx = deck.currentIndex
            let fit = fittedRect(aspect: deck.slideAspect, in: geo.size)
            let p = deck.pointer
            let zoom: CGFloat = (deck.magnify && p != nil) ? 2.2 : 1.0
            let anchor = zoomAnchor(p, fit: fit, in: geo.size)
            ZStack {
                Color.black
                ZStack {
                    if let img = deck.image(index: idx, kind: .slide, pixelWidth: fit.width * 2) {
                        Image(uiImage: img).resizable().interpolation(.high).scaledToFit()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                    }
                    SlideEffectsOverlay(strokes: deck.strokes[idx] ?? [], live: deck.liveStroke,
                                        laser: deck.tool == .laser ? p : nil,
                                        spotlight: deck.tool == .spotlight ? p : nil, fit: fit)
                }
                .scaleEffect(zoom, anchor: anchor)
                .clipped()
                if interactive && mode != .none {
                    PencilCanvas(onBegin: { handleBegin($0, $1) },
                                 onMove: { handleMove($0, $1) },
                                 onEnd: { handleEnd() })
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                }
            }
            .contentShape(Rectangle())
            .modifier(LocalSwipe(enabled: interactive && mode == .none, deck: deck))
        }
    }

    private func zoomAnchor(_ p: CGPoint?, fit: CGRect, in size: CGSize) -> UnitPoint {
        guard let p, size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: (fit.minX + p.x * fit.width) / size.width,
                         y: (fit.minY + p.y * fit.height) / size.height)
    }

    private enum Mode { case draw, erase, pointer, none }
    private var mode: Mode {
        if deck.magnify { return .pointer }
        switch deck.tool {
        case .pen, .highlighter: return .draw
        case .eraser:            return .erase
        case .laser, .spotlight: return .pointer
        case .off:               return .none
        }
    }
    private func handleBegin(_ p: CGPoint, _ force: CGFloat) {
        switch mode {
        case .draw:
            let w: CGFloat = deck.tool == .highlighter ? 0.022 : (0.002 + 0.009 * force)
            deck.beginStroke(Stroke(points: [p], width: w, colorIndex: deck.penColorIndex,
                                    highlighter: deck.tool == .highlighter))
        case .erase:   deck.eraseAt(p)
        case .pointer: deck.pointer = p
        case .none:    break
        }
    }
    private func handleMove(_ p: CGPoint, _ force: CGFloat) {
        switch mode {
        case .draw:    deck.extendStroke(p)
        case .erase:   deck.eraseAt(p)
        case .pointer: deck.pointer = p
        case .none:    break
        }
    }
    private func handleEnd() {
        switch mode {
        case .draw:    deck.commitStroke()
        case .pointer: deck.pointer = nil
        default:       break
        }
    }
}

private struct LocalSwipe: ViewModifier {
    let enabled: Bool
    let deck: LocalDeck
    func body(content: Content) -> some View {
        if enabled {
            content.gesture(DragGesture(minimumDistance: 24).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 48, abs(dx) > abs(dy) * 1.4 else { return }
                if dx < 0 { deck.advance() } else { deck.goPrev() }
            })
        } else { content }
    }
}

/// What the external display shows: the current slide full-bleed on black, with
/// live annotations and the black/white blank overlay.
struct LocalAudienceView: View {
    @Bindable var deck: LocalDeck
    var body: some View {
        ZStack {
            Color.black
            if deck.document != nil {
                LocalSlideView(deck: deck, interactive: false)
            } else {
                Text("Open a PDF on the iPad")
                    .font(.title2).foregroundStyle(.white.opacity(0.6))
            }
            switch deck.blank {
            case .black: Color.black
            case .white: Color.white
            case .none:  EmptyView()
            }
        }
        .ignoresSafeArea()
    }
}
