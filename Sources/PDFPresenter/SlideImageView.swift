// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import PDFKit

/// Shows one cropped region of one page, letterboxed on black, with optional
/// annotation overlay and (for the current slide) laser/pen interaction.
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
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                    if showAnnotations {
                        AnnotationOverlay(model: model, index: index, fit: fit)
                    }
                    if interactive {
                        InteractionLayer(model: model, fit: fit)
                    }
                } else if kind == .notes {
                    Text("No notes\n(this isn't a split / notes PDF)")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
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
        let key = "\(index)|\(kind)|\(model.isSplit)|\(Int(bucket))"
        let img = SlideRenderer.shared.image(page: page, region: region, key: key, pixelWidth: bucket)
        return (img, region.width / region.height)
    }
}

/// Draws committed + live strokes and the laser dot for `index`.
struct AnnotationOverlay: View {
    let model: PresentationModel
    let index: Int
    let fit: CGRect

    var body: some View {
        // Read tracked state here so the view re-evaluates when it changes.
        let strokes = model.strokes[index] ?? []
        let live = (index == model.currentIndex) ? model.liveStroke : nil
        let laser = (index == model.currentIndex && model.tool == .laser) ? model.pointer : nil

        return ZStack {
            Canvas { ctx, _ in
                for s in strokes { draw(s, in: &ctx) }
                if let l = live { draw(l, in: &ctx) }
            }
            .allowsHitTesting(false)

            if let p = laser {
                Circle()
                    .fill(Color.red.opacity(0.75))
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .frame(width: 20, height: 20)
                    .position(x: fit.minX + p.x * fit.width, y: fit.minY + p.y * fit.height)
                    .allowsHitTesting(false)
            }
        }
    }

    private func draw(_ s: Stroke, in ctx: inout GraphicsContext) {
        guard s.points.count > 1 else { return }
        let pts = s.points.map { CGPoint(x: fit.minX + $0.x * fit.width, y: fit.minY + $0.y * fit.height) }
        var path = Path()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        ctx.stroke(path,
                   with: .color(.red),
                   style: StrokeStyle(lineWidth: max(2, s.width * fit.width),
                                      lineCap: .round, lineJoin: .round))
    }
}

/// Transparent layer over the current slide that turns mouse movement into a
/// laser position (hover) or a pen stroke (drag), in normalized slide coords.
struct InteractionLayer: View {
    let model: PresentationModel
    let fit: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard model.tool == .laser else { return }
                switch phase {
                case .active(let loc): model.pointer = norm(loc)
                case .ended:           model.pointer = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard model.tool == .pen else { return }
                        let p = norm(v.location)
                        if model.liveStroke == nil {
                            model.liveStroke = Stroke(points: [p])
                        } else {
                            model.liveStroke?.points.append(p)
                        }
                    }
                    .onEnded { _ in
                        guard model.tool == .pen else { return }
                        model.commitStroke()
                    }
            )
    }

    private func norm(_ loc: CGPoint) -> CGPoint {
        CGPoint(x: clamp((loc.x - fit.minX) / fit.width),
                y: clamp((loc.y - fit.minY) / fit.height))
    }
}
