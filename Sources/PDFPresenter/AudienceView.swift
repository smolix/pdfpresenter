// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI

/// What the audience sees: the current slide full-bleed on black, with laser /
/// pen annotations, and the black/white blank overlay on top.
struct AudienceView: View {
    let model: PresentationModel

    var body: some View {
        ZStack {
            Color.black
            if model.document != nil {
                if model.isSplit {
                    // Beamer split deck: show the left (slide) half as a bitmap;
                    // a PDFView can't crop to half a page.
                    SlideImageView(model: model,
                                   index: model.currentIndex,
                                   kind: .slide,
                                   showAnnotations: true,
                                   interactive: false)
                } else {
                    // Plain PDF: render live so links and embedded media work.
                    LivePDFSlide(model: model)
                }
            } else {
                Text("Open a PDF (⌘O)")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            switch model.blank {
            case .black: Color.black
            case .white: Color.white
            case .none:  EmptyView()
            }
        }
        .ignoresSafeArea()
    }
}
