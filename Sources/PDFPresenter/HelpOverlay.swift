// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI

/// Full-screen cheat-sheet of every keyboard shortcut, shown over the presenter
/// view. Toggled with `?`, the toolbar `?` button, or Help ▸ Keyboard Shortcuts
/// (⌘?). Dismissed with Esc, `?`, or a click.
struct HelpOverlay: View {
    let model: PresentationModel

    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let label: String
    }
    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let items: [Shortcut]
    }

    private let sections: [Section] = [
        Section(title: "Navigate", items: [
            Shortcut(keys: "→ ↓ Space ⇟", label: "Next slide"),
            Shortcut(keys: "← ↑ ⇞", label: "Previous slide"),
            Shortcut(keys: "Home / End", label: "First / last slide"),
            Shortcut(keys: "123 ⏎", label: "Jump to the slide numbered 123"),
            Shortcut(keys: "Tab / G", label: "Slide overview grid"),
        ]),
        Section(title: "Annotate", items: [
            Shortcut(keys: "L", label: "Laser pointer"),
            Shortcut(keys: "D", label: "Pen"),
            Shortcut(keys: "H", label: "Highlighter"),
            Shortcut(keys: "X", label: "Eraser"),
            Shortcut(keys: "S", label: "Spotlight"),
            Shortcut(keys: "Z", label: "Magnifier (zoom to cursor)"),
            Shortcut(keys: "C", label: "Clear this slide's annotations"),
        ]),
        Section(title: "Screen & display", items: [
            Shortcut(keys: "B / W", label: "Blank audience black / white"),
            Shortcut(keys: "F", label: "Toggle audience full-screen"),
            Shortcut(keys: "⌃M", label: "Move audience to next display"),
            Shortcut(keys: "E", label: "Cycle layout preset"),
        ]),
        Section(title: "Timer", items: [
            Shortcut(keys: "P", label: "Pause / resume timer"),
            Shortcut(keys: "R", label: "Reset timer"),
        ]),
        Section(title: "Other", items: [
            Shortcut(keys: "⌘O", label: "Open a PDF"),
            Shortcut(keys: "⌘E", label: "Export annotated PDF"),
            Shortcut(keys: "?", label: "Show / hide this help"),
            Shortcut(keys: "Esc", label: "Exit full-screen → un-blank → cancel tool"),
        ]),
    ]

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 22)]

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Label("Keyboard Shortcuts", systemImage: "keyboard")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Button("Close (Esc)") { model.showHelp = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 26).padding(.vertical, 18)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title.uppercased())
                                    .font(.system(size: 11, weight: .bold)).tracking(0.8)
                                    .foregroundStyle(Color.accentColor)
                                ForEach(section.items) { item in row(item) }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.13),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 26).padding(.bottom, 24)
                }

                Text("The timer starts automatically on your first slide advance.")
                    .font(.callout).foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 18)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.showHelp = false }
        .transition(.opacity)
    }

    @ViewBuilder private func row(_ item: Shortcut) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.keys)
                .font(.system(.callout, design: .rounded).weight(.semibold)).monospaced()
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
                .frame(width: 132, alignment: .leading)
            Text(item.label)
                .font(.callout).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
