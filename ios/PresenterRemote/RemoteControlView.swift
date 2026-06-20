// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import UIKit
import PresenterKit

/// Keynote-style remote: a dominant current slide with a compact, persistent
/// control strip on top, a prominent next-slide preview and notes alongside
/// (landscape) or below (portrait). Swipe the slide to navigate. The iPhone gets
/// a tighter, phone-shaped variant of the same idea.
struct RemoteControlView: View {
    @Bindable var conn: ConnectionModel
    @State private var showOverview = false
    @State private var showConnection = false
    @State private var showJump = false

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(conn: conn, showConnection: $showConnection)
            ControlStrip(conn: conn, showOverview: $showOverview, showJump: $showJump)
            Divider()
            GeometryReader { geo in
                let landscape = geo.size.width >= geo.size.height
                if isPhone {
                    phoneContent(geo: geo, landscape: landscape)
                } else {
                    padContent(geo: geo, landscape: landscape)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showOverview) {
            OverviewSheet(conn: conn) { showOverview = false }
        }
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(conn: conn) { showConnection = false }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showJump) {
            GoToSlideSheet(conn: conn) { showJump = false }
        }
        .onAppear {
            #if DEBUG
            if conn.demoShowJump { showJump = true }
            if conn.demoShowConnection { showConnection = true }
            #endif
        }
    }

    // iPad: dominant slide + a next/notes column (landscape) or row (portrait).
    @ViewBuilder private func padContent(geo: GeometryProxy, landscape: Bool) -> some View {
        if landscape {
            HStack(spacing: 12) {
                SlideStageView(conn: conn, interactive: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 12) {
                    NextCard(conn: conn)
                    NotesCard(conn: conn)
                }
                .frame(width: max(220, geo.size.width * 0.27))
            }
            .padding(12)
        } else {
            VStack(spacing: 12) {
                SlideStageView(conn: conn, interactive: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.size.height * 0.56)
                HStack(spacing: 12) {
                    NextCard(conn: conn).frame(maxWidth: .infinity)
                    NotesCard(conn: conn).frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(12)
        }
    }

    // iPhone: a big slide with a slim next/notes column (landscape) or a compact
    // toggled Next/Notes panel below (portrait) — tight, like Keynote's remote.
    @ViewBuilder private func phoneContent(geo: GeometryProxy, landscape: Bool) -> some View {
        if landscape {
            HStack(spacing: 10) {
                SlideStageView(conn: conn, interactive: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 8) {
                    NextCard(conn: conn)
                    NotesCard(conn: conn)
                }
                .frame(width: max(180, geo.size.width * 0.34))
            }
            .padding(10)
        } else {
            VStack(spacing: 10) {
                SlideStageView(conn: conn, interactive: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PhonePanel(conn: conn)
                    .frame(height: max(150, geo.size.height * 0.32))
            }
            .padding(10)
        }
    }
}

// MARK: - iPhone bottom panel (toggle Next / Notes to save vertical space)

private struct PhonePanel: View {
    @Bindable var conn: ConnectionModel
    @State private var tab = 0   // 0 = next, 1 = notes

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $tab) {
                Text("Next").tag(0)
                Text("Notes").tag(1)
            }
            .pickerStyle(.segmented)

            if tab == 0 { NextCard(conn: conn) } else { NotesCard(conn: conn) }
        }
    }
}

// MARK: - Top bar (connection · counter · timer)

private struct TopBar: View {
    @Bindable var conn: ConnectionModel
    @Binding var showConnection: Bool

    var body: some View {
        let s = conn.state
        HStack(spacing: 12) {
            Button { showConnection = true } label: {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text(conn.macName ?? "Mac").font(.subheadline.weight(.medium)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(white: 0.15), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(s?.currentLabel ?? "—") / \(s?.pageCount ?? 0)")
                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in timer(now: ctx.date) }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
    }

    @ViewBuilder private func timer(now: Date) -> some View {
        let s = conn.state
        if let rem = s?.remaining(now: now) {
            let over = rem < 0
            HStack(spacing: 5) {
                Image(systemName: over ? "exclamationmark.triangle.fill" : "timer")
                Text((over ? "−" : "") + elapsedString(abs(rem)))
                    .monospacedDigit().font(.headline)
            }
            .foregroundStyle(timerColor(rem, talk: s?.talkLength ?? 0))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                Text(elapsedString(s?.elapsed(now: now) ?? 0)).monospacedDigit().font(.headline)
            }
        }
    }
    private func timerColor(_ rem: TimeInterval, talk: Double) -> Color {
        let warn = max(120, talk * 0.15)
        if rem <= 0 { return .red }
        if rem <= warn { return .orange }
        return .primary
    }
}

// MARK: - Control strip (compact, persistent; wraps to extra rows when narrow)

private struct ControlItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void
}

private struct ControlStrip: View {
    @Bindable var conn: ConnectionModel
    @Binding var showOverview: Bool
    @Binding var showJump: Bool
    @State private var width: CGFloat = 0

    private var s: PresenterState? { conn.state }
    private var tool: Tool { s?.tool ?? .off }
    private var drawing: Bool { tool == .pen || tool == .highlighter }

    var body: some View {
        // Tools (and colour swatches while drawing) always show. The remaining
        // controls fill what's left of ~2 rows by priority; the rest collapse
        // into "⋯". So drawing keeps the strip tight (the controls barely matter
        // then), and they reappear as the screen affords — full row on iPad.
        let controls = controlItems
        let budget = controlBudget()
        let inline = Array(controls.prefix(budget))
        let overflow = Array(controls.dropFirst(budget))

        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tools, id: \.0) { (t, icon) in
                StripButton(icon, active: tool == t) { conn.send(.setTool(t)) }
            }
            if drawing {
                ForEach(0..<annotationPalette.count, id: \.self) { i in
                    SwatchButton(index: i, selected: s?.penColorIndex == i) { conn.send(.setPenColor(i)) }
                }
            }
            ForEach(inline) { c in StripButton(c.icon, active: c.active, action: c.action) }
            moreMenu(overflow: overflow)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        })
    }

    /// How many of the priority-ordered controls fit inline within two rows,
    /// after tools, swatches, and the "⋯" menu — the rest overflow into "⋯".
    private func controlBudget() -> Int {
        let perRow = width > 0 ? max(1, Int((width - 28) / 50)) : 7   // 42 button + 8 spacing
        let used = 6 /* tools */ + (drawing ? annotationPalette.count : 0) + 1 /* ⋯ */
        return max(0, min(controlItems.count, perRow * 2 - used))
    }

    private var tools: [(Tool, String)] {
        [(.off, "cursorarrow"), (.laser, "cursorarrow.rays"), (.spotlight, "flashlight.on.fill"),
         (.pen, "pencil.tip"), (.highlighter, "highlighter"), (.eraser, "eraser")]
    }

    // Priority order: Clear first (the one control that matters mid-drawing),
    // then navigation, blanking, presenting, timer.
    private var controlItems: [ControlItem] {
        [ ControlItem(id: "clear", icon: "trash", label: "Clear Annotations", active: false) {
              conn.send(.clearAnnotations) },
          ControlItem(id: "overview", icon: "rectangle.grid.2x2", label: "All Slides", active: false) {
              conn.requestOverview(); showOverview = true },
          ControlItem(id: "jump", icon: "number", label: "Go to Slide", active: false) {
              showJump = true },
          ControlItem(id: "black", icon: "rectangle", label: "Blank Black", active: s?.blank == .black) {
              conn.send(.toggleBlack) },
          ControlItem(id: "white", icon: "rectangle.fill", label: "Blank White", active: s?.blank == .white) {
              conn.send(.toggleWhite) },
          ControlItem(id: "full", icon: "rectangle.inset.filled.on.rectangle",
                      label: s?.presenting == true ? "Windowed" : "Full-Screen", active: s?.presenting == true) {
              conn.send(.toggleFullscreen) },
          // Transport-style: the icon shows the action (▶ to start, ⏸ to pause);
          // never highlighted, so a running timer doesn't read as a blue "pause".
          ControlItem(id: "timer", icon: s?.timerRunning == true ? "pause.fill" : "play.fill",
                      label: s?.timerRunning == true ? "Pause Timer" : "Start Timer", active: false) {
              conn.send(.toggleTimer) },
          ControlItem(id: "reset", icon: "arrow.counterclockwise", label: "Reset Timer", active: false) {
              conn.send(.resetTimer) },
          ControlItem(id: "magnify", icon: "plus.magnifyingglass", label: "Magnifier", active: s?.magnify == true) {
              conn.send(.setMagnify(!(s?.magnify ?? false))) },
        ]
    }

    private func moreMenu(overflow: [ControlItem]) -> some View {
        Menu {
            ForEach(overflow) { c in
                Button(action: c.action) { Label(c.label, systemImage: c.icon) }
            }
            if !overflow.isEmpty { Divider() }
            Picker("Layout", selection: Binding(get: { s?.preset ?? .notesRight },
                                                set: { conn.send(.setPreset($0)) })) {
                ForEach(LayoutPreset.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if (s?.externalDisplays ?? 0) > 1 {
                Button("Move Audience to Next Display") { conn.send(.cycleDisplay) }
            }
            Menu("Talk Length") {
                Button("No target") { conn.send(.setTalkLength(0)) }
                ForEach([5, 10, 15, 20, 25, 30, 40, 45, 60], id: \.self) { m in
                    Button("\(m) min") { conn.send(.setTalkLength(Double(m * 60))) }
                }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 42, height: 42)
                .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct StripButton: View {
    let icon: String
    var active = false
    let action: () -> Void
    init(_ icon: String, active: Bool = false, action: @escaping () -> Void) {
        self.icon = icon; self.active = active; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17))
                .frame(width: 42, height: 42)
                .background(active ? Color.blue : Color(white: 0.15),
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(active ? Color.white : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// A pen/highlighter colour swatch sized like a strip button so it flows in line.
private struct SwatchButton: View {
    let index: Int
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle().fill(remoteColor(index)).frame(width: 24, height: 24)
                        .overlay(Circle().stroke(.white.opacity(selected ? 0.95 : 0.25),
                                                 lineWidth: selected ? 3 : 1))
                )
        }
        .buttonStyle(.plain)
    }
}

/// A simple left-to-right flow layout: lays children in a row until they don't
/// fit, then wraps to the next row. Keeps the control strip fully visible at any
/// width instead of scrolling buttons off-screen.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            x += sz.width + spacing
            rowHeight = max(rowHeight, sz.height)
        }
        widest = max(widest, x - spacing)
        let width = proposal.width ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + lineSpacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowHeight = max(rowHeight, sz.height)
        }
    }
}

// MARK: - Next slide + notes cards

private struct NextCard: View {
    @Bindable var conn: ConnectionModel
    var body: some View {
        let s = conn.state
        let nextImg = (s?.hasNext == true) ? conn.slideImages[(s?.currentIndex ?? -1) + 1] : nil
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Button { conn.send(.next) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12))
                    if let img = nextImg {
                        Image(uiImage: img).resizable().scaledToFit().padding(2)
                    } else if s?.hasNext == false {
                        Text("End of deck").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .aspectRatio(CGFloat(s?.slideAspect ?? 16.0 / 9.0), contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(s?.hasNext != true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotesCard: View {
    @Bindable var conn: ConnectionModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Group {
                if conn.state?.isSplit == true, let img = conn.notesImage {
                    ScrollView { Image(uiImage: img).resizable().scaledToFit() }
                } else if let t = conn.state?.notesText, !t.isEmpty {
                    ScrollView { Text(t).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    Text("No notes for this slide").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Sheets

private struct OverviewSheet: View {
    @Bindable var conn: ConnectionModel
    let dismiss: () -> Void
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(0..<(conn.state?.pageCount ?? 0), id: \.self) { i in
                        Button {
                            conn.send(.goToIndex(i)); dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12))
                                    if let img = conn.overviewImages[i] {
                                        Image(uiImage: img).resizable().scaledToFit().padding(1)
                                    } else { ProgressView().tint(.white) }
                                }
                                .aspectRatio(CGFloat(conn.state?.slideAspect ?? 16.0 / 9.0), contentMode: .fit)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(i == conn.state?.currentIndex ? Color.blue : .white.opacity(0.15),
                                            lineWidth: i == conn.state?.currentIndex ? 3 : 1))
                                Text(conn.state.map { _ in "\(i + 1)" } ?? "")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("All Slides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
        }
        .preferredColorScheme(.dark)
    }
}


/// Go-to-slide with a self-contained dark number pad — no system keyboard, so
/// no white floating bubble on iPad. A hardware keyboard (digits / Return /
/// Delete) works too.
private struct GoToSlideSheet: View {
    @Bindable var conn: ConnectionModel
    let dismiss: () -> Void
    @State private var digits = ""
    @FocusState private var keyFocus: Bool

    private func tap(_ n: Int) { if digits.count < 6 { digits += String(n) } }
    private func backspace() { if !digits.isEmpty { digits.removeLast() } }
    private func go() { if !digits.isEmpty { conn.send(.goToLabel(digits)) }; dismiss() }

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        VStack(spacing: 18) {
            Text("Go to Slide").font(.headline)
            Text(digits.isEmpty ? "0" : digits)
                .font(.system(size: 46, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(digits.isEmpty ? .secondary : .primary)
                .frame(height: 54)

            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(1...9, id: \.self) { n in key(text: "\(n)") { tap(n) } }
                key(icon: "xmark") { digits = "" }
                key(text: "0") { tap(0) }
                key(icon: "delete.left") { backspace() }
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                Button("Go") { go() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                    .disabled(digits.isEmpty)
            }
        }
        .padding(22)
        .frame(maxWidth: 380, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .presentationDetents([.height(500)])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled()
        .focused($keyFocus)
        .onKeyPress { press in
            if let c = press.characters.first, let n = c.wholeNumberValue, c.isNumber { tap(n); return .handled }
            switch press.key {
            case .return: go(); return .handled
            case .delete: backspace(); return .handled
            default: return .ignored
            }
        }
        .onAppear { keyFocus = true }
    }

    private func key(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.title.weight(.medium))
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).foregroundStyle(.white)
    }
    private func key(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).foregroundStyle(.white)
    }
}

private struct ConnectionSheet: View {
    @Bindable var conn: ConnectionModel
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected to").font(.caption).foregroundStyle(.secondary)
                        Text(conn.macName ?? "—").font(.headline)
                    }
                    Spacer()
                    Circle().fill(.green).frame(width: 9, height: 9)
                }
                .padding(14)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))

                Button { conn.requestOverview(); conn.send(.goToIndex(conn.state?.currentIndex ?? 0)) } label: {
                    Label("Re-sync slides", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).controlSize(.large)

                Button(role: .destructive) { conn.forget(); dismiss() } label: {
                    Label("Forget this Mac", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).controlSize(.large)

                Text("The remote controls one Mac at a time. Paired devices reconnect "
                     + "automatically; forgetting requires re-entering the code from the Mac's "
                     + "Remote ▸ Pairing & Status panel.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
        }
        .preferredColorScheme(.dark)
    }
}
