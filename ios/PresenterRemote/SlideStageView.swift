// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import UIKit
import PresenterKit

/// The current slide (streamed from the Mac) with committed + in-flight ink.
/// In cursor mode a horizontal swipe advances/goes back; with a drawing or
/// pointer tool, Apple Pencil / touch ink, erase, or move the laser/spotlight.
/// The previous slide is held on screen until the new one loads (no black flash).
struct SlideStageView: View {
    @Bindable var conn: ConnectionModel
    var interactive: Bool

    var body: some View {
        GeometryReader { geo in
            let aspect = CGFloat(conn.state?.slideAspect ?? 16.0 / 9.0)
            let fit = fittedRect(aspect: aspect, in: geo.size)
            let p = conn.localPointer
            let zoom: CGFloat = (magnify && p != nil) ? 2.2 : 1.0
            let anchor = zoomAnchor(p, fit: fit, in: geo.size)
            ZStack {
                Color.black
                ZStack {
                    if let img = conn.displayImage {
                        Image(uiImage: img).resizable().interpolation(.high).scaledToFit()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                    }
                    SlideEffectsOverlay(strokes: conn.currentStrokes, live: conn.liveStroke,
                                        laser: tool == .laser ? p : nil,
                                        spotlight: tool == .spotlight ? p : nil,
                                        fit: fit)
                }
                .scaleEffect(zoom, anchor: anchor)
                .clipped()
                if conn.displayImage == nil {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Waiting for slide…").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if interactive && mode != .none {
                    PencilCanvas(onBegin: { handleBegin($0, $1) },
                                 onMove: { handleMove($0, $1) },
                                 onEnd: { handleEnd() })
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                }
            }
            .contentShape(Rectangle())
            .modifier(SwipeToNavigate(enabled: mode == .none, conn: conn))
        }
    }

    private func zoomAnchor(_ p: CGPoint?, fit: CGRect, in size: CGSize) -> UnitPoint {
        guard let p, size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: (fit.minX + p.x * fit.width) / size.width,
                         y: (fit.minY + p.y * fit.height) / size.height)
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
        case .pointer: conn.localPointer = p; conn.sendPointer(p)
        case .none:    break
        }
    }
    private func handleMove(_ p: CGPoint, _ force: CGFloat) {
        switch mode {
        case .draw:    conn.extendStroke(p)
        case .erase:   conn.sendErase(p)
        case .pointer: conn.localPointer = p; conn.sendPointer(p)
        case .none:    break
        }
    }
    private func handleEnd() {
        switch mode {
        case .draw:    conn.endStroke()
        case .pointer: conn.localPointer = nil; conn.sendPointer(nil)
        default:       break
        }
    }
}

/// Attaches a horizontal swipe→navigate gesture only when enabled (cursor mode),
/// so it never competes with the Pencil drawing layer.
private struct SwipeToNavigate: ViewModifier {
    let enabled: Bool
    let conn: ConnectionModel
    func body(content: Content) -> some View {
        if enabled {
            content.gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        guard abs(dx) > 48, abs(dx) > abs(dy) * 1.4 else { return }
                        conn.send(dx < 0 ? .next : .prev)
                    }
            )
        } else {
            content
        }
    }
}

/// Draws committed + live strokes, the spotlight dim, and the laser dot in the
/// slide's normalized coordinates — the same effects the desktop audience shows,
/// so the presenter sees exactly what the room sees. Fills the geometry (so the
/// spotlight can dim the whole stage) and maps points into `fit`.
struct SlideEffectsOverlay: View {
    let strokes: [Stroke]
    let live: Stroke?
    var laser: CGPoint? = nil
    var spotlight: CGPoint? = nil
    let fit: CGRect

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for s in strokes { draw(s, &ctx) }
                if let l = live { draw(l, &ctx) }
            }
            if let sp = spotlight {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.62)))
                    ctx.blendMode = .destinationOut
                    let r = max(fit.width, fit.height) * 0.11
                    let c = point(sp)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(.black))
                }
            }
            if let l = laser {
                Circle().fill(Color.red.opacity(0.75))
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .frame(width: 20, height: 20)
                    .position(point(l))
            }
        }
        .allowsHitTesting(false)
    }

    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: fit.minX + p.x * fit.width, y: fit.minY + p.y * fit.height)
    }
    private func draw(_ s: Stroke, _ ctx: inout GraphicsContext) {
        guard s.points.count > 1 else { return }
        let pts = s.points.map { point($0) }
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
