# PDF Presenter

A native macOS PDF slide presenter with a true **presenter view / second-screen**
mode — like Keynote or PowerPoint, but for plain PDF decks. Built on PDFKit +
SwiftUI/AppKit.

When an external display is connected, the **slides go full-screen on the
projector** automatically while your laptop shows the **presenter view**: the
current slide, the next slide, speaker notes, a timer and clock, with a slide
overview, annotation tools, a spotlight and magnifier, a talk-length countdown,
and screen-blanking.

<!-- A screenshot of the presenter view goes well here. -->

## Why

Preview.app has no presenter view, Keynote/PowerPoint don't open PDFs nicely, and
the dedicated tools are either clunky or expensive. This is a small, fast, native
app that does one thing well.

## Features

- **Second-screen presenter view** that auto-routes to an external display.
- **Speaker notes** from Beamer "notes on second screen" splits *or* a
  Markdown/text sidecar (see below).
- **Rearrangeable layout presets**: Notes Right, Notes Bottom, Slide Focus.
- **Slide overview** grid — jump anywhere by click or by typing a number.
- **Timer** with a wall clock and an optional **talk-length countdown** that
  turns amber, then red, as you run over.
- **Annotation tools**: laser pointer, multi-colour pen, highlighter, eraser,
  and a **spotlight** — all shown live on the audience screen.
- **Magnifier** that zooms into the slide around the cursor.
- **Black / white screen** blanking to pull focus.
- **Annotations persist** next to the PDF and can be **exported as a flattened,
  annotated PDF**.
- Works with **0, 1, or 2 external displays**; pick which one is the audience.

## Speaker notes (Beamer)

Notes come from the **Beamer "notes on second screen"** format. In your `.tex`:

```latex
\setbeameroption{show notes on second screen=right}
```

That produces double-wide pages (slide | notes). PDF Presenter detects this
automatically and splits each page: the **left half** (the slide) goes to the
projector and the current/next cards, the **right half** (the notes) shows in the
Notes card. Plain (non-split) PDFs work too — they just show no notes.

Auto-detection treats a deck as split when its page aspect ratio exceeds ~2.1:1.
You can override it under **View ▸ Notes: Auto-detect / Split (Beamer) / None**.
"Split (Beamer)" only takes effect on genuinely double-wide pages, so forcing it
on a normal 16:9 deck safely shows the full slide rather than cropping it in half.

### Markdown / text sidecar (plain PDFs)

For decks that aren't split, put a notes file next to the PDF with the **same
base name** and a `.md`, `.markdown`, `.txt`, or `.notes` extension. Start each
slide's notes with a header line — `# 3`, `## 3`, or `# Slide 3`:

```markdown
# 1
Welcome — set the agenda.

# 7
KEY RESULT: emphasize the 3× speedup.
- mention the batch-size caveat
```

The notes for the current slide then appear in the Notes card.

## Requirements

- macOS 14 or later
- A Swift 5.9+ toolchain (Xcode or the Command Line Tools)

## Build & run

```bash
# Dev run (opens an Open dialog, or pass a file):
swift run PDFPresenter /path/to/slides.pdf

# Build a double-clickable app bundle:
./build.sh
open PDFPresenter.app --args /path/to/slides.pdf
# ...or just: open PDFPresenter.app   (then ⌘O)
```

`build.sh` runs `swift build -c release` and assembles `PDFPresenter.app`. Build
artifacts live outside the source tree; nothing to clean up in the repo.

## Two-display behavior

- **External display connected:** the presenter view fills your built-in screen;
  the audience slide covers the external display full-screen automatically.
  Hot-plugging a display re-routes the windows live.
- **Two external displays:** the largest external is used by default. Choose a
  specific one under **Present ▸ Audience Display**, or press **M** to cycle.
- **Single display (e.g. testing):** presenter and audience show as two windows.
  Press **F** (or *Present ▸ Toggle Audience Full-Screen*) to cover the screen.

## Keyboard

| Key | Action |
| --- | --- |
| → / ↓ / Space / PageDown | Next slide |
| ← / ↑ / PageUp | Previous slide |
| Home / End | First / last slide |
| `123` then Return | Jump to slide 123 |
| Tab / `G` | Slide overview grid |
| `B` / `W` | Blank audience to black / white |
| `L` | Laser pointer (follows the cursor over the current slide) |
| `D` | Pen — draw on the current slide |
| `H` | Highlighter |
| `X` | Eraser |
| `S` | Spotlight (dim everything but a circle) |
| `Z` | Magnifier (zoom into the cursor) |
| `C` | Clear annotations on this slide |
| `P` / `R` | Pause-resume / reset timer |
| `E` | Cycle layout preset |
| `M` | Move audience to the next display |
| `F` | Toggle audience full-screen |
| `⌘E` | Export annotated PDF |
| Esc | Exit full-screen → un-blank → cancel magnifier → cancel tool |

The timer starts automatically on the first slide advance.

## Annotations

Pick a tool from the toolbar or with the keys above: **pen**, **highlighter**,
**eraser**, **laser**, **spotlight**, plus a **magnifier**. The pen and
highlighter share a six-colour palette. Everything you draw or point to appears
on the audience screen in real time.

Annotations are saved automatically to a sidecar file next to the PDF
(`<name>.pdfpres.json`) and reload the next time you open the deck. Use
**File ▸ Export Annotated PDF…** (⌘E) to write a flattened copy with your
drawings burned in.

## Timer & countdown

The timer counts up and starts on your first slide advance. Set a target under
the toolbar `⋯` menu ▸ **Talk length**; the status bar then shows time
**remaining**, turning amber as you near the limit and red (with a `−`) once
you're over.

## Layout presets

Switch with the toolbar `⋯` menu, **View ▸ Layout** (⌘1/⌘2/⌘3), or by pressing
**E** to cycle:

- **Notes Right** — big current slide, next + notes stacked on the right.
- **Notes Bottom** — current + next on top, notes spanning the bottom.
- **Slide Focus** — a dominant current slide with small next/notes cards below.

Cards always hug the slide's real aspect ratio, so there's no letterboxing.

## Project layout

```
Sources/PDFPresenter/
  main.swift              NSApplication entry point
  AppDelegate.swift       windows, display routing, menu, keyboard, snapshot mode
  PresentationModel.swift @Observable shared state (nav, split, timer, preset…)
  SlideRenderer.swift     cropped-region PDF → NSImage rendering + cache
  SlideImageView.swift    one slide/notes region + annotation & interaction layers
  AudienceView.swift      full-bleed audience screen
  PresenterView.swift     toolbar, layout presets, cards, status bar, overview
  UIHelpers.swift         aspect-fit + formatting helpers
tools/make_test_pdf.swift generates a Beamer-style split test deck
```

## Development

Generate a synthetic Beamer-style split deck for testing:

```bash
swift tools/make_test_pdf.swift test-split.pdf 12   # 12 double-wide pages
```

Render the presenter and audience views off-screen to PNG (handy for verifying
layout changes without a second monitor):

```bash
swift run PDFPresenter --snapshot /tmp/shots test-split.pdf
# writes presenter-<preset>.png and audience.png to /tmp/shots
```

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
Copyright 2026 Alex Smola.
