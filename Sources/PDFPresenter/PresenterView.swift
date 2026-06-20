// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import PresenterKit

/// Window-level actions the presenter UI delegates back to the AppDelegate.
struct PresenterActions {
    var openFile: () -> Void = {}
    var toggleFullscreen: () -> Void = {}
    var cycleDisplay: () -> Void = {}
    var exportAnnotated: () -> Void = {}
}

private let pageBG = Color(red: 0.09, green: 0.09, blue: 0.10)

struct PresenterView: View {
    @Bindable var model: PresentationModel
    var actions = PresenterActions()

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model, actions: actions)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    pageBG
                    if model.document == nil {
                        emptyState
                    } else {
                        let f = frames(model.preset, in: geo.size)
                        place(SlideCard(model: model, index: model.currentIndex, kind: .slide,
                                        label: "Current", accent: true,
                                        interactive: true, showAnnotations: true), f.current)
                        place(nextCard, f.next)
                        place(NotesCard(model: model), f.notes)
                        place(StatusBar(model: model), f.status)
                    }
                }
            }
        }
        .background(Color.black)
        .overlay { if model.showOverview { OverviewGrid(model: model) } }
        .overlay { if model.showHelp { HelpOverlay(model: model) } }
    }

    @ViewBuilder private var nextCard: some View {
        if let n = model.nextIndex {
            SlideCard(model: model, index: n, kind: .slide, label: "Next")
        } else {
            SlideCard(model: model, index: -1, kind: .slide, label: "Next")
        }
    }

    private func place<V: View>(_ view: V, _ r: CGRect) -> some View {
        view.frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Open a PDF to begin (⌘O)").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Layout regions per preset

    private func frames(_ preset: LayoutPreset, in size: CGSize)
        -> (current: CGRect, next: CGRect, notes: CGRect, status: CGRect) {
        let pad: CGFloat = 14
        let statusH: CGFloat = 56
        let W = size.width, H = size.height
        let status = CGRect(x: pad, y: H - statusH, width: W - 2 * pad, height: statusH - pad)
        let cx = pad, cy = pad
        let cw = W - 2 * pad
        let ch = H - statusH - pad      // content area height

        switch preset {
        case .notesRight:
            let rightW = (cw - pad) * 0.33
            let leftW = cw - pad - rightW
            let nextH = (ch - pad) * 0.46
            return (
                CGRect(x: cx, y: cy, width: leftW, height: ch),
                CGRect(x: cx + leftW + pad, y: cy, width: rightW, height: nextH),
                CGRect(x: cx + leftW + pad, y: cy + nextH + pad, width: rightW, height: ch - nextH - pad),
                status)
        case .notesBottom:
            let topH = (ch - pad) * 0.64
            let rightW = (cw - pad) * 0.32
            let leftW = cw - pad - rightW
            return (
                CGRect(x: cx, y: cy, width: leftW, height: topH),
                CGRect(x: cx + leftW + pad, y: cy, width: rightW, height: topH),
                CGRect(x: cx, y: cy + topH + pad, width: cw, height: ch - topH - pad),
                status)
        case .slideFocus:
            let bottomH = (ch - pad) * 0.24
            let halfW = (cw - pad) / 2
            return (
                CGRect(x: cx, y: cy, width: cw, height: ch - bottomH - pad),
                CGRect(x: cx, y: cy + ch - bottomH, width: halfW, height: bottomH),
                CGRect(x: cx + halfW + pad, y: cy + ch - bottomH, width: halfW, height: bottomH),
                status)
        }
    }
}

// MARK: - Slide card (hugs the slide's aspect ratio)

struct SlideCard: View {
    let model: PresentationModel
    let index: Int
    let kind: RegionKind
    var label: String? = nil
    var accent: Bool = false
    var interactive: Bool = false
    var showAnnotations: Bool = false
    var topAlign: Bool = false

    var body: some View {
        GeometryReader { geo in
            let aspect = (kind == .slide) ? model.slideAspect : model.notesAspect
            let s = fittedSize(aspect: aspect, in: geo.size)
            let x = (geo.size.width - s.width) / 2
            let y = topAlign ? 0 : (geo.size.height - s.height) / 2
            content(size: s)
                .frame(width: s.width, height: s.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(accent ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.12),
                                      lineWidth: accent ? 2 : 1)
                )
                .overlay(alignment: .topLeading) { labelBadge }
                .shadow(color: .black.opacity(0.5), radius: 11, x: 0, y: 5)
                .offset(x: x, y: y)
        }
    }

    @ViewBuilder private func content(size: CGSize) -> some View {
        if let img = renderedImage(pixelWidth: size.width * 2) {
            let zoom: CGFloat = (model.magnify && model.pointer != nil
                                 && kind == .slide && index == model.currentIndex) ? 2.2 : 1.0
            let anchor = model.pointer.map { UnitPoint(x: $0.x, y: $0.y) } ?? .center
            ZStack {
                Color.black
                ZStack {
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height)
                    if showAnnotations {
                        AnnotationOverlay(model: model, index: index, fit: CGRect(origin: .zero, size: size))
                    }
                }
                .scaleEffect(zoom, anchor: anchor)
                .clipped()
                if interactive {
                    InteractionLayer(model: model, fit: CGRect(origin: .zero, size: size))
                }
            }
        } else {
            ZStack {
                Color(white: 0.14)
                Text(placeholder).multilineTextAlignment(.center)
                    .font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    private var placeholder: String {
        if kind == .notes { return "No notes" }
        return index < 0 ? "End of deck" : "—"
    }

    private var labelBadge: some View {
        Group {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(7)
            }
        }
    }

    private func renderedImage(pixelWidth: CGFloat) -> NSImage? {
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
        return SlideRenderer.shared.image(page: page, region: region, key: key, pixelWidth: bucket)
    }
}

// MARK: - Notes card (image half for split decks, text for sidecar notes)

struct NotesCard: View {
    let model: PresentationModel

    var body: some View {
        if model.isSplit {
            SlideCard(model: model, index: model.currentIndex, kind: .notes, label: "Notes", topAlign: true)
        } else {
            NotesTextCard(model: model)
        }
    }
}

struct NotesTextCard: View {
    let model: PresentationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(0.6)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.leading, 10).padding(.top, 9).padding(.bottom, 6)
            ScrollView {
                Text(text)
                    .font(.system(.title3))
                    .foregroundStyle(hasNotes ? .white : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var hasNotes: Bool { model.currentNotesText != nil }
    private var text: String {
        model.currentNotesText ?? (model.hasSidecarNotes ? "—" : "No notes for this slide")
    }
}

// MARK: - Status bar (timer / countdown / clock / progress)

struct StatusBar: View {
    let model: PresentationModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 18) {
                timerView
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(clockString()).monospacedDigit()
                }
                .foregroundStyle(.secondary)

                if model.blank != .none {
                    Label(model.blank == .black ? "Black" : "White", systemImage: "eye.slash")
                        .font(.callout).foregroundStyle(.orange)
                }
                if model.magnify {
                    Label("Zoom", systemImage: "plus.magnifyingglass").font(.callout).foregroundStyle(.blue)
                }

                Spacer()

                Text("Slide \(model.currentLabel) of \(model.pageCount)")
                    .monospacedDigit().foregroundStyle(.secondary)
                ProgressCapsule(
                    fraction: model.pageCount > 0
                        ? CGFloat(model.currentIndex + 1) / CGFloat(model.pageCount) : 0
                )
                .frame(width: 170, height: 6)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var timerView: some View {
        if let rem = model.remaining {
            let over = rem < 0
            HStack(spacing: 7) {
                Image(systemName: over ? "exclamationmark.triangle.fill" : "timer")
                Text((over ? "−" : "") + elapsedString(abs(rem)))
                    .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(timerColor(rem))
            Text("/ \(elapsedString(model.talkLength))")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        } else {
            HStack(spacing: 7) {
                Image(systemName: "timer")
                Text(elapsedString(model.elapsed))
                    .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
            }
        }
    }

    private func timerColor(_ rem: TimeInterval) -> Color {
        let warn = max(120, model.talkLength * 0.15)
        if rem <= 0 { return .red }
        if rem <= warn { return .orange }
        return .white
    }
}

struct ProgressCapsule: View {
    let fraction: CGFloat
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(Color.accentColor).frame(width: max(4, g.size.width * fraction))
            }
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Bindable var model: PresentationModel
    let actions: PresenterActions

    var body: some View {
        HStack(spacing: 10) {
            Button { actions.openFile() } label: { Image(systemName: "folder") }
                .help("Open PDF (⌘O)")

            Divider().frame(height: 18)

            Button { model.goPrev() } label: { Image(systemName: "chevron.left") }
            Text("\(model.currentLabel) / \(model.pageCount)")
                .monospacedDigit().frame(minWidth: 58)
                .help("Document page \(model.currentLabel) — physical slide \(model.pageCount == 0 ? 0 : model.currentIndex + 1) of \(model.pageCount)")
            Button { model.goNext() } label: { Image(systemName: "chevron.right") }

            Divider().frame(height: 18)

            Button { model.toggleTimer() } label: {
                Image(systemName: model.timerRunning ? "pause.fill" : "play.fill")
            }.help("Start/pause timer (P)")
            Button { model.resetTimer() } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Reset timer (R)")

            Spacer(minLength: 8)

            Picker("", selection: $model.tool) {
                Image(systemName: "cursorarrow").tag(Tool.off)
                Image(systemName: "cursorarrow.rays").tag(Tool.laser)
                Image(systemName: "flashlight.on.fill").tag(Tool.spotlight)
                Image(systemName: "pencil.tip").tag(Tool.pen)
                Image(systemName: "highlighter").tag(Tool.highlighter)
                Image(systemName: "eraser").tag(Tool.eraser)
            }
            .pickerStyle(.segmented).frame(width: 208).labelsHidden()

            if model.tool == .pen || model.tool == .highlighter {
                HStack(spacing: 5) {
                    ForEach(0..<annotationNSColors.count, id: \.self) { i in
                        Circle().fill(annotationColor(i)).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.primary.opacity(model.penColorIndex == i ? 0.9 : 0.25),
                                                     lineWidth: model.penColorIndex == i ? 2 : 1))
                            .onTapGesture { model.penColorIndex = i }
                    }
                }
            }

            Button { model.magnify.toggle() } label: {
                Image(systemName: model.magnify ? "plus.magnifyingglass" : "magnifyingglass")
            }
            .foregroundStyle(model.magnify ? Color.accentColor : .primary).help("Magnifier (Z)")
            Button { model.clearAnnotations() } label: { Image(systemName: "trash") }
                .help("Clear annotations (C)")

            Divider().frame(height: 18)

            Button { model.toggleBlack() } label: { Image(systemName: "rectangle.fill") }
                .foregroundStyle(model.blank == .black ? Color.accentColor : .primary).help("Blank black (B)")
            Button { model.toggleWhite() } label: { Image(systemName: "rectangle") }
                .foregroundStyle(model.blank == .white ? Color.accentColor : .primary).help("Blank white (W)")
            Button { model.showOverview.toggle() } label: { Image(systemName: "square.grid.3x3") }
                .help("Overview (Tab)")
            Button { model.showHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                .help("Keyboard shortcuts (?)")

            Menu {
                Picker("Layout", selection: $model.preset) {
                    ForEach(LayoutPreset.allCases, id: \.self) { p in Text(p.title).tag(p) }
                }
                Picker("Notes", selection: $model.splitMode) {
                    Text("Auto-detect").tag(SplitMode.auto)
                    Text("Split (Beamer)").tag(SplitMode.splitRight)
                    Text("No notes").tag(SplitMode.single)
                }
                Picker("Talk length", selection: $model.talkLength) {
                    Text("No target").tag(TimeInterval(0))
                    ForEach([5, 10, 15, 20, 25, 30, 40, 45, 60], id: \.self) { m in
                        Text("\(m) min").tag(TimeInterval(m * 60))
                    }
                }
                Divider()
                Button("Export Annotated PDF…") { actions.exportAnnotated() }
                Divider()
                Button("Toggle Audience Full-Screen (F)") { actions.toggleFullscreen() }
                Button("Move Audience to Next Display (⌃M)") { actions.cycleDisplay() }
                Divider()
                Button("Keyboard Shortcuts (?)") { model.showHelp = true }
            } label: { Image(systemName: "slider.horizontal.3") }
            .menuStyle(.borderlessButton).frame(width: 38)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .buttonStyle(.borderless)
        .background(.bar)
    }
}

// MARK: - Overview grid

struct OverviewGrid: View {
    let model: PresentationModel
    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("All Slides").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Button("Close (Esc)") { model.showOverview = false }
                }
                .padding()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(0..<max(0, model.pageCount)), id: \.self) { i in
                            VStack(spacing: 5) {
                                SlideImageView(model: model, index: i, kind: .slide)
                                    .aspectRatio(model.slideAspect, contentMode: .fit)
                                    .frame(height: 118)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(i == model.currentIndex ? Color.accentColor : Color.white.opacity(0.2),
                                                    lineWidth: i == model.currentIndex ? 3 : 1)
                                    )
                                Text(model.label(for: i)).font(.caption)
                                    .foregroundStyle(i == model.currentIndex ? Color.accentColor : .white)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.goTo(i); model.showOverview = false }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}
