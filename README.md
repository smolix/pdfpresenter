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

- **Second-screen presenter view** with explicit **per-role display assignment**
  (pick the presenter screen, the audience screen, or swap them). Starts windowed;
  you choose when to go full-screen on the projector.
- **iOS companion** ("PDF Presenter" for iPhone/iPad) — a Wi-Fi/Bluetooth remote
  with a live presenter mirror and Apple-Pencil drawing (see below).
- **Open Recent** — your recently opened decks under **File ▸ Open Recent**.
- **Live PDF rendering** for plain decks, so **clickable links and embedded
  media** work on the audience screen (Beamer split decks use a fast bitmap crop).
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

Split decks are shown to the audience as a bitmap crop of the left half (a
PDFView can't display half a page). **Plain PDFs are rendered live with a real
`PDFView`**, so **URL links and embedded media stay interactive** on the audience
screen — click a link on the projected slide and it follows it, and following an
in-document link keeps the presenter view in sync.

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

- **Start windowed:** the app opens on one screen with the presenter and a
  windowed audience — it does **not** grab an external display full-screen on
  its own. Present when you're ready (see below). Hot-plugging a display
  re-routes the windows live.
- **Go full-screen on the projector:** press **F**, click the audience window's
  green **zoom** button, or use *Present ▸ Toggle Audience Full-Screen*. Press
  **F**/**Esc** to return it to a window.
- **Choosing displays:** under **Present** you can pin the **Presenter Display**
  and the **Audience Display** to specific screens (each is listed by its real
  name, so two identical monitors are still distinguishable), or **Swap
  Presenter / Audience Displays** in one step. With three or more screens, press
  **⌃M** to cycle the audience through the non-presenter displays — it always
  advances from the display the audience is *currently* on, so the first press
  moves it.
- **Single display (e.g. testing):** presenter and audience show as two windows.
  The audience window is fully movable and minimizable; drag it to any display
  and press **F**, click its green **zoom** button, or use *Present ▸ Toggle
  Audience Full-Screen* to cover **that** display. Press **F**/**Esc** again to
  return it to a window. The full-screen cover is a separate, dedicated window
  (it never restyles the live view), so it can't flash black mid-talk.

## Keyboard

| Key | Action |
| --- | --- |
| → / ↓ / Space / PageDown | Next slide |
| ← / ↑ / PageUp | Previous slide |
| Home / End | First / last slide |
| `123` then Return | Jump to the slide **numbered** 123 (the document's page label) |
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
| `⌃M` | Move audience to the next display |
| `F` | Toggle audience full-screen on/off |
| `?` | Show / hide the keyboard-shortcut help |
| `⌘E` | Export annotated PDF |
| Esc | Exit full-screen → un-blank → cancel magnifier → cancel tool |

The timer starts automatically on the first slide advance. Press **`?`** any time
(or **Help ▸ Keyboard Shortcuts**, ⌘?) for an on-screen cheat-sheet of every key.

### Page numbers

The slide counter and the type-a-number jump use the **document's own page
labels** when the PDF defines them — i.e. the numbers actually printed on your
slides. So if the title page isn't counted, or numbering restarts, or overlay
frames repeat a number, typing that number jumps to the matching slide (the
header shows the label over the physical slide count, e.g. `3 / 30`, and the
tooltip spells out both). PDFs without page labels fall back to plain 1-based
order, so nothing changes for them.

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

## iOS companion app (PDF Presenter Remote)

A SwiftUI iPhone/iPad app that **controls the Mac** over Wi-Fi or Bluetooth. The
PDF always stays on the Mac — the companion is a remote, not a viewer:

- **iPhone** — a presenter's remote: next/prev, jump-to-slide, black/white blank,
  timer, tools, layout, and audience full-screen, with a live mirror of the
  current + next slide, notes, timer/countdown and slide counter.
- **iPad** — additionally an **Apple Pencil drawing surface**: ink directly on
  the current slide (pressure → width, the same six-colour palette, highlighter,
  eraser) and it appears live on the audience screen. Drag to move a **laser** or
  **spotlight** pointer, or set the zoom focus for the magnifier.

It shares the exact `Stroke` / tool / palette types with the Mac (the
`PresenterKit` package), so ink lands pixel-identically on the projector.

### Connection & pairing

Transport is **Multipeer Connectivity** — it auto-selects infrastructure Wi-Fi,
peer-to-peer Wi-Fi, or Bluetooth, so it keeps working on guest networks that
block device-to-device traffic, and even with Wi-Fi off (Bluetooth). The session
is encrypted, and access is gated by a **one-time pairing code**:

1. On the Mac, open **Remote ▸ Pairing & Status…** (⇧⌘R) to show a 6-digit code.
2. On the device, open **PDF Presenter** (the iOS app), tap your Mac, and enter the code.
3. Paired devices are remembered and reconnect silently. Revoke them with
   **Remote ▸ Forget Paired Devices**.

Both apps ask for **Local Network** permission on first run (allow it). Only your
own devices should be paired; the code stops a stranger on the same Wi-Fi from
taking over.

### Building & running the companion (no paid account needed)

The iOS app is its own Xcode project, generated from `ios/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
sudo port install xcodegen          # MacPorts
cd ios && xcodegen generate         # writes PresenterRemote.xcodeproj
open PresenterRemote.xcodeproj
```

In Xcode, you can run it on your **own** iPhone/iPad with a free Apple ID — no
Apple Developer Program required:

1. **Settings → Accounts**: add your Apple ID. On the target's **Signing &
   Capabilities** tab pick your **Personal Team** (the bundle ID
   `org.smola.pdfpresenter.remote` is already set).
2. On the device (iOS 17+): **Settings → Privacy & Security → Developer Mode →
   On**, then restart.
3. Pick the device as the run destination and **Run**. First launch:
   **Settings → General → VPN & Device Management → trust** your developer
   profile.

Free-provisioning caveats: the build **expires after 7 days** (rebuild from Xcode
to refresh — or use AltStore/SideStore to auto-refresh), max 3 sideloaded apps
per device. For quick UI tweaks you can also run it in the **Simulator** (no
signing), though Apple Pencil drawing needs a real iPad. Requires **iOS 17+**.

## Project layout

```
Sources/PresenterKit/      shared by macOS + iOS (a SwiftPM library)
  Model.swift             Stroke, Tool/BlankMode/SplitMode/LayoutPreset, palette
  Protocol.swift          PresenterMessage / PresenterState / RemoteCommand wire types
  PeerLink.swift          Multipeer Connectivity host/client transport
  Geometry.swift          aspect-fit + time-format helpers
Sources/PDFPresenter/      the macOS app
  main.swift              NSApplication entry point
  AppDelegate.swift       windows, display routing, cover window, menu, keyboard
  PresentationModel.swift @Observable shared state (nav, split, timer, preset…)
  RemoteServer.swift      hosts the iOS companion, applies control, streams state
  RemotePanel.swift       pairing-code + connection-status panel
  SlideRenderer.swift     cropped-region PDF → NSImage rendering + cache
  SlideImageView.swift    one slide/notes region + annotation & interaction layers
  SlidePDFView.swift      live PDFView audience slide (links/media) for plain decks
  AudienceView.swift      full-bleed audience screen (live PDF or bitmap crop)
  PresenterView.swift     toolbar, layout presets, cards, status bar, overview
  HelpOverlay.swift       keyboard-shortcut cheat-sheet overlay
  UIHelpers.swift         NSColor palette + RegionKind
ios/                       the iOS companion (own Xcode project via XcodeGen)
  project.yml             XcodeGen spec → PresenterRemote.xcodeproj
  PresenterRemote/        ConnectionModel, PairingView, SlideStageView, controls
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
