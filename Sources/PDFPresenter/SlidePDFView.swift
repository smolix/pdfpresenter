// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import PDFKit
import PresenterKit

/// The audience slide for non-split (non-Beamer) decks, rendered with a real
/// `PDFView` so URL links and embedded media stay live — the bitmap path can't
/// do that. Split decks keep the bitmap crop (a PDFView can't show half a page).
///
/// The annotation overlay, spotlight/laser, blank overlay and magnifier are
/// layered on top exactly as in `SlideImageView`, fitted to the same letterbox
/// rect the PDFView uses, so everything lines up with the projected page.
struct LivePDFSlide: View {
    let model: PresentationModel

    var body: some View {
        GeometryReader { geo in
            let index = model.currentIndex                     // tracked read → re-renders on nav
            let fit = fittedRect(aspect: model.slideAspect, in: geo.size)
            let zoom = zoomScale
            let anchor = zoomAnchor(fit: fit, in: geo.size)
            ZStack {
                Color.black
                ZStack {
                    PDFPageView(model: model)
                        .id(model.docToken)   // rebuild & reload the PDFView when the deck is rebuilt
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                    AnnotationOverlay(model: model, index: index, fit: fit)
                }
                .scaleEffect(zoom, anchor: anchor)
                .clipped()
            }
            .contentShape(Rectangle())
        }
    }

    private var zoomScale: CGFloat {
        model.magnify ? model.magnifyScale : 1.0
    }
    private func zoomAnchor(fit: CGRect, in size: CGSize) -> UnitPoint {
        let p = model.pointer ?? model.lastPointer
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: (fit.minX + p.x * fit.width) / size.width,
                         y: (fit.minY + p.y * fit.height) / size.height)
    }
}

/// A `PDFView` locked to a single page that mirrors `model.currentIndex`.
///
/// It loads its *own* `PDFDocument` from the deck URL rather than sharing
/// `model.document`: the bitmap renderer touches `model.document` on a
/// background queue, and PDFKit is not safe to drive from two places at once,
/// so the live view gets an independent copy.
struct PDFPageView: NSViewRepresentable {
    let model: PresentationModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode = .singlePage
        v.displaysPageBreaks = false
        v.displaysAsBook = false
        v.autoScales = true
        v.backgroundColor = .black
        v.interpolationQuality = .high
        // The page should fill the view; we've already sized the view to the
        // slide's aspect ratio, so auto-scale fits it edge to edge.
        context.coordinator.attach(v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        context.coordinator.sync(v)
    }

    static func dismantleNSView(_ v: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        let model: PresentationModel
        private weak var view: PDFView?
        private var loadedToken = -1
        private var suppressPageNotification = false

        init(model: PresentationModel) { self.model = model }

        func attach(_ v: PDFView) {
            view = v
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged, object: v)
        }
        func detach() {
            NotificationCenter.default.removeObserver(self, name: .PDFViewPageChanged, object: view)
        }

        func sync(_ v: PDFView) {
            // (Re)load when the open deck changes.
            if model.docToken != loadedToken {
                loadedToken = model.docToken
                v.document = model.documentURL.flatMap { PDFDocument(url: $0) }
                v.autoScales = true
            }
            guard let doc = v.document,
                  model.currentIndex >= 0, model.currentIndex < doc.pageCount,
                  let page = doc.page(at: model.currentIndex) else { return }
            if v.currentPage != page {
                suppressPageNotification = true
                v.go(to: page)
                suppressPageNotification = false
            }
            v.autoScales = true   // refit after any layout/page change
        }

        /// Following an in-document GoTo link moves the PDFView's page; mirror
        /// that back into the model so the presenter view stays in sync.
        @objc func pageChanged(_ note: Notification) {
            guard !suppressPageNotification,
                  let v = view, let doc = v.document, let page = v.currentPage else { return }
            let idx = doc.index(for: page)
            if idx >= 0, idx != model.currentIndex { model.goTo(idx) }
        }
    }
}
