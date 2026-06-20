// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import UIKit
import PresenterKit

/// Shows the current slide streamed from the Mac, overlays committed + in-flight
/// ink, and (on iPad / when `interactive`) turns Apple Pencil or touch into
/// strokes, erases, or a laser/spotlight pointer depending on the active tool.
struct SlideStageView: View {
    @Bindable var conn: ConnectionModel
    var interactive: Bool

    var body: some View {
        GeometryReader { geo in
            let aspect = CGFloat(conn.state?.slideAspect ?? 16.0 / 9.0)
            let fit = fittedRect(aspect: aspect, in: geo.size)
            ZStack {
                Color.black
                if let idx = conn.state?.currentIndex, let img = conn.slideImages[idx] {
                    Image(uiImage: img).resizable().interpolation(.high).scaledToFit()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                } else {
                    ProgressView().tint(.white)
                }
                StrokeOverlay(strokes: conn.currentStrokes, live: conn.liveStroke, fit: fit)
                if interactive && mode != .none {
                    PencilCanvas(onBegin: { handleBegin($0, $1) },
                                 onMove: { handleMove($0, $1) },
                                 onEnd: { handleEnd() })
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                }
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: Input routing

    private enum Mode { case draw, erase, pointer, none }
    private var tool: Tool { conn.state?.tool ?? .off }
    private var magnify: Bool { conn.state?.magnify ?? false }
    private var mode: Mode {
        if magnify { return .pointer }
        switch tool {
        case .pen, .highlighter: return .draw
        case .eraser:            return .erase
        case .laser, .spotlight: return .pointer
        case .off:               return .none
        }
    }

    private func handleBegin(_ p: CGPoint, _ force: CGFloat) {
        switch mode {
        case .draw:
            let width: CGFloat = tool == .highlighter ? 0.022 : (0.002 + 0.009 * force)
            conn.beginStroke(Stroke(points: [p], width: width,
                                    colorIndex: conn.state?.penColorIndex ?? 0,
                                    highlighter: tool == .highlighter))
        case .erase:   conn.sendErase(p)
        case .pointer: conn.sendPointer(p)
        case .none:    break
        }
    }
    private func handleMove(_ p: CGPoint, _ force: CGFloat) {
        switch mode {
        case .draw:    conn.extendStroke(p)
        case .erase:   conn.sendErase(p)
        case .pointer: conn.sendPointer(p)
        case .none:    break
        }
    }
    private func handleEnd() {
        switch mode {
        case .draw:    conn.endStroke()
        case .pointer: conn.sendPointer(nil)
        default:       break
        }
    }
}

/// Draws committed + live strokes in normalized coordinates, matching the
/// Mac/audience rendering so the iPad preview lines up.
struct StrokeOverlay: View {
    let strokes: [Stroke]
    let live: Stroke?
    let fit: CGRect

    var body: some View {
        Canvas { ctx, _ in
            for s in strokes { draw(s, &ctx) }
            if let l = live { draw(l, &ctx) }
        }
        .frame(width: fit.width, height: fit.height)
        .position(x: fit.midX, y: fit.midY)
        .allowsHitTesting(false)
    }

    private func draw(_ s: Stroke, _ ctx: inout GraphicsContext) {
        guard s.points.count > 1 else { return }
        let pts = s.points.map { CGPoint(x: $0.x * fit.width, y: $0.y * fit.height) }
        var path = Path()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        let color = remoteColor(s.colorIndex)
        let w = max(1.5, s.width * fit.width)
        ctx.stroke(path, with: .color(s.highlighter ? color.opacity(0.35) : color),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
}

/// A transparent UIKit layer that reports normalized touch points and Apple
/// Pencil force. Prefers a Pencil over fingers (basic palm rejection) and uses
/// coalesced touches for smooth, high-rate ink.
struct PencilCanvas: UIViewRepresentable {
    var onBegin: (CGPoint, CGFloat) -> Void
    var onMove: (CGPoint, CGFloat) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true
        v.handlers = (onBegin, onMove, onEnd)
        return v
    }
    func updateUIView(_ v: TouchView, context: Context) {
        v.handlers = (onBegin, onMove, onEnd)
    }

    final class TouchView: UIView {
        var handlers: ((CGPoint, CGFloat) -> Void, (CGPoint, CGFloat) -> Void, () -> Void)?
        private var active: UITouch?

        private func point(_ t: UITouch) -> CGPoint {
            let loc = t.preciseLocation(in: self)
            return CGPoint(x: clamp(loc.x / max(1, bounds.width)),
                           y: clamp(loc.y / max(1, bounds.height)))
        }
        private func force(_ t: UITouch) -> CGFloat {
            guard t.type == .pencil, t.maximumPossibleForce > 0 else { return 0.5 }
            return clamp(t.force / t.maximumPossibleForce)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard active == nil else { return }
            let t = touches.first(where: { $0.type == .pencil }) ?? touches.first
            guard let t else { return }
            active = t
            handlers?.0(point(t), force(t))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = active, touches.contains(t) else { return }
            if let coalesced = event?.coalescedTouches(for: t) {
                for ct in coalesced { handlers?.1(point(ct), force(ct)) }
            } else {
                handlers?.1(point(t), force(t))
            }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

        private func finish(_ touches: Set<UITouch>) {
            guard let t = active, touches.contains(t) else { return }
            active = nil
            handlers?.2()
        }
    }
}
