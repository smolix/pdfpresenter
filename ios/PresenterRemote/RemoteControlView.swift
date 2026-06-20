// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import PresenterKit

/// The connected companion. On iPad it's a big drawing stage with a control
/// column; on iPhone it's a stacked controller. Mirrors the desktop presenter:
/// current/next slides, notes, timer, counter, and every control.
struct RemoteControlView: View {
    @Bindable var conn: ConnectionModel
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(conn: conn)
            Divider()
            if hSize == .regular {
                HStack(spacing: 0) {
                    SlideStageView(conn: conn, interactive: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    Divider()
                    ScrollView { ControlsView(conn: conn).padding(16) }
                        .frame(width: 360)
                        .background(Color(white: 0.08))
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        SlideStageView(conn: conn, interactive: true)
                            .aspectRatio(CGFloat(conn.state?.slideAspect ?? 16.0 / 9.0), contentMode: .fit)
                            .frame(maxHeight: 280)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                        ControlsView(conn: conn)
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: - Header (counter + timer + clock)

struct HeaderView: View {
    @Bindable var conn: ConnectionModel
    @State private var showJump = false

    var body: some View {
        let s = conn.state
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(s?.documentName.isEmpty == false ? s!.documentName : "PDF Presenter")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                Text("Slide \(s?.currentLabel ?? "—") of \(s?.pageCount ?? 0)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in timer(now: ctx.date) }
            Menu {
                Button("Re-sync") { conn.send(.first); conn.send(.goToIndex(conn.state?.currentIndex ?? 0)) }
                Button("Forget this Mac", role: .destructive) { conn.forget() }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private func timer(now: Date) -> some View {
        let s = conn.state
        if let rem = s?.remaining(now: now) {
            let over = rem < 0
            HStack(spacing: 5) {
                Image(systemName: over ? "exclamationmark.triangle.fill" : "timer")
                Text((over ? "−" : "") + elapsedString(abs(rem)))
                    .monospacedDigit().font(.title3.weight(.semibold))
            }
            .foregroundStyle(timerColor(rem, talk: s?.talkLength ?? 0))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                Text(elapsedString(s?.elapsed(now: now) ?? 0)).monospacedDigit().font(.title3.weight(.semibold))
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

// MARK: - Controls

struct ControlsView: View {
    @Bindable var conn: ConnectionModel
    @State private var showJump = false
    @State private var jumpText = ""

    private var s: PresenterState? { conn.state }

    var body: some View {
        VStack(spacing: 18) {
            navSection
            toolsSection
            screenSection
            timerSection
            nextNotesSection
        }
        .sheet(isPresented: $showJump) { jumpSheet }
    }

    // Navigation
    private var navSection: some View {
        Section("Navigate") {
            HStack(spacing: 10) {
                BigButton(system: "chevron.left", label: "Prev") { conn.send(.prev) }
                BigButton(system: "chevron.right", label: "Next", prominent: true) { conn.send(.next) }
            }
            HStack(spacing: 10) {
                Tile("First", "backward.end") { conn.send(.first) }
                Tile("Go To", "number") { jumpText = ""; showJump = true }
                Tile("Last", "forward.end") { conn.send(.last) }
                Tile("Overview", "square.grid.2x2", active: false) { conn.send(.cyclePreset) }
            }
        }
    }

    // Tools
    private var toolsSection: some View {
        Section("Tools") {
            let cols = [GridItem(.adaptive(minimum: 72), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(toolItems, id: \.0) { (tool, label, icon) in
                    Tile(label, icon, active: s?.tool == tool) { conn.send(.setTool(tool)) }
                }
            }
            if s?.tool == .pen || s?.tool == .highlighter {
                HStack(spacing: 8) {
                    ForEach(0..<annotationPalette.count, id: \.self) { i in
                        Circle().fill(remoteColor(i)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white.opacity(s?.penColorIndex == i ? 0.95 : 0.25),
                                                     lineWidth: s?.penColorIndex == i ? 3 : 1))
                            .onTapGesture { conn.send(.setPenColor(i)) }
                    }
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                Tile("Magnify", "plus.magnifyingglass", active: s?.magnify == true) {
                    conn.send(.setMagnify(!(s?.magnify ?? false)))
                }
                Tile("Clear", "trash") { conn.send(.clearAnnotations) }
            }
        }
    }

    private var toolItems: [(Tool, String, String)] {
        [(.off, "Cursor", "cursorarrow"),
         (.laser, "Laser", "cursorarrow.rays"),
         (.spotlight, "Spotlight", "flashlight.on.fill"),
         (.pen, "Pen", "pencil.tip"),
         (.highlighter, "Marker", "highlighter"),
         (.eraser, "Eraser", "eraser")]
    }

    // Screen / display
    private var screenSection: some View {
        Section("Screen") {
            HStack(spacing: 10) {
                Tile("Black", "rectangle.fill", active: s?.blank == .black) { conn.send(.toggleBlack) }
                Tile("White", "rectangle", active: s?.blank == .white) { conn.send(.toggleWhite) }
                Tile(s?.presenting == true ? "Windowed" : "Full-Screen",
                     "rectangle.inset.filled.on.rectangle", active: s?.presenting == true) {
                    conn.send(.toggleFullscreen)
                }
            }
            HStack(spacing: 10) {
                Tile("Next Display", "display.2", disabled: (s?.externalDisplays ?? 0) < 2) { conn.send(.cycleDisplay) }
                Menu {
                    ForEach(LayoutPreset.allCases, id: \.self) { p in
                        Button(p.title) { conn.send(.setPreset(p)) }
                    }
                } label: { TileLabel("Layout", "rectangle.3.group") }
            }
        }
    }

    // Timer
    private var timerSection: some View {
        Section("Timer") {
            HStack(spacing: 10) {
                Tile(s?.timerRunning == true ? "Pause" : "Start",
                     s?.timerRunning == true ? "pause.fill" : "play.fill",
                     active: s?.timerRunning == true) { conn.send(.toggleTimer) }
                Tile("Reset", "arrow.counterclockwise") { conn.send(.resetTimer) }
                Menu {
                    Button("No target") { conn.send(.setTalkLength(0)) }
                    ForEach([5, 10, 15, 20, 25, 30, 40, 45, 60], id: \.self) { m in
                        Button("\(m) min") { conn.send(.setTalkLength(Double(m * 60))) }
                    }
                } label: { TileLabel("Length", "hourglass") }
            }
        }
    }

    // Next slide + notes
    private var nextNotesSection: some View {
        Section("Up Next & Notes") {
            HStack(alignment: .top, spacing: 12) {
                if let n = s?.currentIndex, s?.hasNext == true, let img = conn.slideImages[n + 1] {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(width: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15)))
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.15))
                        .frame(width: 120, height: 68)
                        .overlay(Text("End").font(.caption).foregroundStyle(.secondary))
                }
                notesView
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var notesView: some View {
        if conn.state?.isSplit == true, let img = conn.notesImage {
            Image(uiImage: img).resizable().scaledToFit()
                .frame(maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let t = conn.state?.notesText, !t.isEmpty {
            ScrollView { Text(t).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 120)
        } else {
            Text("No notes").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var jumpSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Type the slide number shown on the slide.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Slide", text: $jumpText)
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .frame(width: 160)
                Spacer()
            }
            .padding()
            .navigationTitle("Go to Slide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showJump = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") { conn.send(.goToLabel(jumpText)); showJump = false }
                        .disabled(jumpText.filter(\.isNumber).isEmpty)
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}

// MARK: - Reusable controls

/// A titled group with a small header.
private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Tile: View {
    let label: String, system: String
    var active = false, disabled = false
    let action: () -> Void
    init(_ label: String, _ system: String, active: Bool = false, disabled: Bool = false,
         action: @escaping () -> Void) {
        self.label = label; self.system = system; self.active = active
        self.disabled = disabled; self.action = action
    }
    var body: some View {
        Button(action: action) { TileLabel(label, system, active: active) }
            .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.35 : 1)
    }
}

private struct TileLabel: View {
    let label: String, system: String
    var active = false
    init(_ label: String, _ system: String, active: Bool = false) {
        self.label = label; self.system = system; self.active = active
    }
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: system).font(.title3)
            Text(label).font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity).frame(height: 56)
        .background(active ? Color.blue.opacity(0.22) : Color(white: 0.15),
                    in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(active ? Color.blue : .primary)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(active ? Color.blue : Color.clear, lineWidth: 1.5))
    }
}

private struct BigButton: View {
    let system: String, label: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: system).font(.title2.weight(.semibold))
                Text(label).font(.headline)
            }
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(prominent ? Color.blue : Color(white: 0.17),
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(prominent ? Color.white : .primary)
        }
        .buttonStyle(.plain)
    }
}
