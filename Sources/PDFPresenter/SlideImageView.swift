// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import PDFKit

/// Shows one cropped region of one page, letterboxed on black, with optional
/// annotation overlay, magnifier, and (for the current slide) tool interaction.
struct SlideImageView: View {
    let model: PresentationModel
    let index: Int
    let kind: RegionKind
    var showAnnotations: Bool = false
    var interactive: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let (img, aspect) = rendered(pixelWidth: geo.size.width * 2) {
                    let fit = fittedRect(aspect: aspect, in: geo.size)
                    let zoom = zoomScale
                    let anchor = zoomAnchor(fit: fit, in: geo.size)
                    ZStack {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                        if showAnnotations {
                            AnnotationOverlay(model: model, index: index, fit: fit)
                        }
                    }
                    .scaleEffect(zoom, anchor: anchor)
                    .clipped()
                    if interactive {
                        InteractionLayer(model: model, fit: fit)
                    }
                } else if kind == .notes {
                    Text("No notes")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private var zoomScale: CGFloat {
        (model.magnify && model.pointer != nil && index == model.currentIndex) ? 2.2 : 1.0
    }
    private func zoomAnchor(fit: CGRect, in size: CGSize) -> UnitPoint {
        guard let p = model.pointer, size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: (fit.minX + p.x * fit.width) / size.width,
                         y: (fit.minY + p.y * fit.height) / size.height)
    }

    private func rendered(pixelWidth: CGFloat) -> (NSImage, CGFloat)? {
        guard let doc = model.document, index >= 0, index < model.pageCount,
              let page = doc.page(at: index) else { return nil }
        let region: CGRect
        switch kind {
        case .slide:
            region = model.slideRegion(for: page)
        case .notes:
            guard let n = model.notesRegion(for: page) else { return nil }
            region = n
        }
        guard region.width > 0, region.height > 0 else { return nil }
        let bucket = max(64, (pixelWidth / 128).rounded() * 128)
        let key = "\(model.docToken)|\(index)|\(kind)|\(model.isSplit)|\(Int(bucket))"
        let img = SlideRenderer.shared.image(page: page, region: region, key: key, pixelWidth: bucket)
        return (img, region.width / region.height)
    }
}

/// Draws committed + live strokes, the spotlight dim, and the laser dot.
struct AnnotationOverlay: View {
    let model: PresentationModel
    let index: Int
    let fit: CGRect

    var body: some View {
        // Read tracked state here so the view re-evaluates when it changes.
        let strokes = model.strokes[index] ?? []
        let isCurrent = index == model.currentIndex
        let live = isCurrent ? model.liveStroke : nil
        let laser = (isCurrent && model.tool == .laser) ? model.pointer : nil
        let spot = (isCurrent && model.tool == .spotlight) ? model.pointer : nil

        return ZStack {
            Canvas { ctx, _ in
                for s in strokes { draw(s, in: &ctx) }
                if let l = live { draw(l, in: &ctx) }
            }
            .allowsHitTesting(false)

            if let sp = spot {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.62)))
                    ctx.blendMode = .destinationOut
                    let r = max(fit.width, fit.height) * 0.11
                    let c = point(sp)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(.black))
                }
                .allowsHitTesting(false)
            }

            if let p = laser {
                Circle()
                    .fill(Color.red.opacity(0.75))
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .frame(width: 20, height: 20)
                    .position(point(p))
                    .allowsHitTesting(false)
            }
        }
    }

    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: fit.minX + p.x * fit.width, y: fit.minY + p.y * fit.height)
    }

    private func draw(_ s: Stroke, in ctx: inout GraphicsContext) {
        guard s.points.count > 1 else { return }
        let pts = s.points.map { point($0) }
        var path = Path()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        let color = annotationColor(s.colorIndex)
        let w = max(2, s.width * fit.width)
        let style = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        ctx.stroke(path, with: .color(s.highlighter ? color.opacity(0.35) : color), style: style)
    }
}

/// Transparent layer over the current slide that turns mouse movement into the
/// active tool's effect (laser/spotlight position, pen/highlighter stroke, erase).
struct InteractionLayer: View {
    let model: PresentationModel
    let fit: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): model.pointer = norm(loc)
                case .ended:           model.pointer = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = norm(v.location)
                        model.pointer = p
                        switch model.tool {
                        case .pen, .highlighter:
                            if model.liveStroke == nil { model.beginStroke(at: p) }
                            else { model.extendStroke(to: p) }
                        case .eraser:
                            model.eraseAt(p)
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        if model.tool == .pen || model.tool == .highlighter { model.commitStroke() }
                    }
            )
    }

    private func norm(_ loc: CGPoint) -> CGPoint {
        CGPoint(x: clamp((loc.x - fit.minX) / fit.width),
                y: clamp((loc.y - fit.minY) / fit.height))
    }
}
