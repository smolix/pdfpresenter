// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import UIKit
import PresenterKit

/// The presenter view when this device drives the show (no Mac): the current
/// slide (drawable), next slide, notes, timer and tools on the iPad/iPhone,
/// while the audience slide goes to a connected external display.
struct LocalPresenterView: View {
    @Bindable var deck: LocalDeck
    let onClose: () -> Void

    @State private var showOverview = false
    @State private var showJump = false
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        VStack(spacing: 0) {
            header
            controlStrip
            Divider()
            GeometryReader { geo in
                let landscape = geo.size.width >= geo.size.height
                content(geo: geo, landscape: landscape)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showOverview) { LocalOverviewSheet(deck: deck) { showOverview = false } }
        .sheet(isPresented: $showJump) {
            GoToSlideSheet(onGo: { deck.goToLabel($0) }) { showJump = false }
        }
        .onAppear { PresentationSession.shared.deck = deck }
        .onDisappear { PresentationSession.shared.deck = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30).background(Color(white: 0.15), in: Circle())
            }.buttonStyle(.plain)

            HStack(spacing: 6) {
                let on = PresentationSession.shared.externalConnected
                Image(systemName: on ? "tv.fill" : "tv").foregroundStyle(on ? .green : .secondary)
                Text(on ? "On display" : "No display").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(deck.currentLabel) / \(deck.pageCount)")
                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in timerView }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
    }

    @ViewBuilder private var timerView: some View {
        if let rem = deck.remaining {
            let over = rem < 0
            HStack(spacing: 5) {
                Image(systemName: over ? "exclamationmark.triangle.fill" : "timer")
                Text((over ? "−" : "") + elapsedString(abs(rem))).monospacedDigit().font(.headline)
            }
            .foregroundStyle(rem <= 0 ? .red : (rem <= max(120, deck.talkLength * 0.15) ? .orange : .primary))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                Text(elapsedString(deck.elapsed)).monospacedDigit().font(.headline)
            }
        }
    }

    // MARK: Control strip

    private var drawing: Bool { deck.tool == .pen || deck.tool == .highlighter }
    private let tools: [(Tool, String)] = [
        (.off, "cursorarrow"), (.laser, "cursorarrow.rays"), (.spotlight, "flashlight.on.fill"),
        (.pen, "pencil.tip"), (.highlighter, "highlighter"), (.eraser, "eraser")]

    private var controlStrip: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tools, id: \.0) { (t, icon) in
                StripButton(icon, active: deck.tool == t) { deck.tool = t }
            }
            if drawing {
                ForEach(0..<annotationPalette.count, id: \.self) { i in
                    SwatchButton(index: i, selected: deck.penColorIndex == i) { deck.penColorIndex = i }
                }
            }
            StripButton("plus.magnifyingglass", active: deck.magnify) { deck.magnify.toggle() }
            StripButton("trash") { deck.clearAnnotations() }
            StripButton("rectangle", active: deck.blank == .black) { deck.toggleBlack() }
            StripButton("rectangle.fill", active: deck.blank == .white) { deck.toggleWhite() }
            StripButton(deck.timerRunning ? "pause.fill" : "play.fill") { deck.toggleTimer() }
            StripButton("arrow.counterclockwise") { deck.resetTimer() }
            StripButton("rectangle.grid.2x2") { showOverview = true }
            StripButton("number") { showJump = true }
            moreMenu
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private var moreMenu: some View {
        Menu {
            Picker("Notes split", selection: $deck.splitMode) {
                Text("Auto-detect").tag(SplitMode.auto)
                Text("Split (Beamer)").tag(SplitMode.splitRight)
                Text("No split").tag(SplitMode.single)
            }
            Menu("Talk Length") {
                Button("No target") { deck.talkLength = 0 }
                ForEach([5, 10, 15, 20, 25, 30, 40, 45, 60], id: \.self) { m in
                    Button("\(m) min") { deck.talkLength = Double(m * 60) }
                }
            }
            Divider()
            Button("Open another PDF…", action: onClose)
        } label: {
            Image(systemName: "ellipsis").frame(width: 42, height: 42)
                .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Content

    @ViewBuilder private func content(geo: GeometryProxy, landscape: Bool) -> some View {
        if landscape {
            HStack(spacing: 12) {
                LocalSlideView(deck: deck, interactive: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 12) { nextCard; notesCard }
                    .frame(width: max(200, geo.size.width * (isPhone ? 0.34 : 0.27)))
            }.padding(12)
        } else {
            VStack(spacing: 12) {
                LocalSlideView(deck: deck, interactive: true)
                    .frame(maxWidth: .infinity).frame(height: geo.size.height * (isPhone ? 0.5 : 0.56))
                HStack(spacing: 12) {
                    nextCard.frame(maxWidth: .infinity)
                    notesCard.frame(maxWidth: .infinity)
                }.frame(maxHeight: .infinity)
            }.padding(12)
        }
    }

    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Button { deck.advance() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12))
                    if let n = deck.nextIndex, let img = deck.image(index: n, kind: .slide, pixelWidth: 600) {
                        Image(uiImage: img).resizable().scaledToFit().padding(2)
                    } else {
                        Text("End of deck").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(deck.slideAspect, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
            }
            .buttonStyle(.plain).disabled(deck.nextIndex == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Group {
                if deck.isSplit, let img = deck.image(index: deck.currentIndex, kind: .notes, pixelWidth: 900) {
                    ScrollView { Image(uiImage: img).resizable().scaledToFit() }
                } else {
                    Text("No notes (Beamer split decks only)")
                        .font(.callout).foregroundStyle(.secondary)
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

/// Overview grid for a local deck — renders thumbnails straight from the PDF.
private struct LocalOverviewSheet: View {
    @Bindable var deck: LocalDeck
    let dismiss: () -> Void
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(0..<deck.pageCount, id: \.self) { i in
                        Button { deck.goTo(i); dismiss() } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12))
                                    if let img = deck.image(index: i, kind: .slide, pixelWidth: 360) {
                                        Image(uiImage: img).resizable().scaledToFit().padding(1)
                                    }
                                }
                                .aspectRatio(deck.slideAspect, contentMode: .fit)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(i == deck.currentIndex ? Color.blue : .white.opacity(0.15),
                                            lineWidth: i == deck.currentIndex ? 3 : 1))
                                Text(deck.label(for: i)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(16)
            }
            .navigationTitle("All Slides").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
        }
        .preferredColorScheme(.dark)
    }
}
