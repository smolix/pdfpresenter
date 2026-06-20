// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import AppKit
import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

/// Borderless windows refuse key status by default; allow it so the audience
/// cover can still receive events if needed.
final class SlideWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PresentationModel()

    private var presenterWindow: NSWindow!
    private var audienceWindow: SlideWindow!
    private var keyMonitor: Any?
    private var audienceCovering = false
    private var gotoBuffer = ""
    private var pendingURL: URL?
    private var audienceScreenChoice: CGDirectDisplayID?   // user override; nil = automatic
    private var displayMenu: NSMenu?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--snapshot") {
            runSnapshotMode()
            return
        }

        model.loadPreset()
        setupMenu()
        setupWindows()
        arrangeWindows()
        installKeyMonitor()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if let u = pendingURL {
            openURL(u)
        } else if let path = CommandLine.arguments.dropFirst().first(where: { $0.lowercased().hasSuffix(".pdf") }) {
            openURL(URL(fileURLWithPath: path))
        } else {
            DispatchQueue.main.async { [weak self] in
                if self?.model.document == nil { self?.openDocumentAction(nil) }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let u = urls.first else { return }
        if presenterWindow == nil { pendingURL = u } else { openURL(u) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Windows

    private func setupWindows() {
        let actions = PresenterActions(
            openFile: { [weak self] in self?.openDocumentAction(nil) },
            toggleFullscreen: { [weak self] in self?.toggleAudienceFullscreen() },
            presentOnSecond: { [weak self] in self?.arrangeWindows(present: true) }
        )

        let presenter = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        presenter.title = "Presenter"
        presenter.contentView = NSHostingView(rootView: PresenterView(model: model, actions: actions))
        presenter.center()
        presenter.setFrameAutosaveName("PresenterWindow")
        presenterWindow = presenter

        let audience = SlideWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        audience.title = "Audience"
        audience.backgroundColor = .black
        audience.contentView = NSHostingView(rootView: AudienceView(model: model))
        audienceWindow = audience

        presenter.makeKeyAndOrderFront(nil)
        audience.orderFront(nil)
    }

    // MARK: Display routing (no hardcoded display count)

    private func displayID(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    private func isBuiltin(_ s: NSScreen) -> Bool { CGDisplayIsBuiltin(displayID(s)) != 0 }

    /// Screen that should hold the presenter view: the built-in panel if there
    /// is one, otherwise the current main screen.
    private func presenterScreen() -> NSScreen {
        NSScreen.screens.first(where: isBuiltin) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Screen that should hold the audience view: a display other than the
    /// presenter's. Honors a user override, else prefers an external display,
    /// else the largest remaining one. nil when only one display is attached.
    private func audienceScreen(excluding presenter: NSScreen) -> NSScreen? {
        let others = NSScreen.screens.filter { $0 != presenter }
        guard !others.isEmpty else { return nil }
        if let id = audienceScreenChoice, let s = others.first(where: { displayID($0) == id }) { return s }
        let externals = others.filter { !isBuiltin($0) }
        let pool = externals.isEmpty ? others : externals
        return pool.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    @objc private func screensChanged() { arrangeWindows() }

    private func arrangeWindows(present: Bool = false) {
        guard presenterWindow != nil, audienceWindow != nil else { return }
        let presScreen = presenterScreen()
        if let ext = audienceScreen(excluding: presScreen) {
            presenterWindow.setFrame(presScreen.visibleFrame, display: true)
            presenterWindow.makeKeyAndOrderFront(nil)
            makeAudienceCover(on: ext)
        } else {
            // Single display: presenter fills it; audience is a window unless asked to present.
            if present {
                makeAudienceCover(on: presScreen)
            } else {
                uncoverAudience(on: presScreen)
                presenterWindow.setFrame(presScreen.visibleFrame, display: true)
            }
            presenterWindow.makeKeyAndOrderFront(nil)
        }
        rebuildDisplayMenu()
    }

    private func makeAudienceCover(on screen: NSScreen) {
        audienceWindow.styleMask = [.borderless]
        audienceWindow.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        audienceWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        audienceWindow.setFrame(screen.frame, display: true)
        audienceWindow.orderFrontRegardless()
        audienceCovering = true
    }

    private func uncoverAudience(on screen: NSScreen? = nil) {
        let s = screen ?? audienceWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        audienceWindow.level = .normal
        audienceWindow.collectionBehavior = [.managed]
        audienceWindow.styleMask = [.titled, .closable, .resizable]
        audienceWindow.title = "Audience"
        audienceWindow.setFrame(
            NSRect(x: s.visibleFrame.minX + 40, y: s.visibleFrame.minY + 40, width: 960, height: 540),
            display: true)
        audienceWindow.orderFront(nil)
        audienceCovering = false
    }

    private func toggleAudienceFullscreen() {
        if audienceCovering {
            uncoverAudience()
        } else {
            let screen = audienceScreen(excluding: presenterScreen())
                ?? audienceWindow.screen ?? presenterScreen()
            makeAudienceCover(on: screen)
        }
        presenterWindow.makeKeyAndOrderFront(nil)
    }

    private func cycleAudienceDisplay() {
        let others = NSScreen.screens.filter { $0 != presenterScreen() }
        guard others.count > 1 else { NSSound.beep(); return }
        let ids = others.map { displayID($0) }
        let current = audienceScreenChoice
            ?? audienceScreen(excluding: presenterScreen()).map { displayID($0) }
        if let cur = current, let i = ids.firstIndex(of: cur) {
            audienceScreenChoice = ids[(i + 1) % ids.count]
        } else {
            audienceScreenChoice = ids.first
        }
        arrangeWindows()
    }

    // MARK: Open

    @objc func openDocumentAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { openURL(url) }
    }

    private func openURL(_ url: URL) {
        model.load(url: url)
        presenterWindow?.title = "Presenter — " + url.lastPathComponent
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func advance() { model.startTimerIfNeeded(); model.goNext() }

    private func handleKey(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) { return false }   // leave ⌘-shortcuts to the menu

        let code = e.keyCode
        let ch = (e.charactersIgnoringModifiers ?? "").lowercased()

        if model.showOverview {
            switch code {
            case 53:           model.showOverview = false; return true   // esc
            case 123, 126:     model.goPrev(); return true
            case 124, 125, 49: model.goNext(); return true
            case 36:           model.showOverview = false; return true
            default:           break
            }
        }

        switch code {
        case 123, 126:     model.goPrev(); return true                   // left / up
        case 124, 125, 49: advance(); return true                        // right / down / space
        case 116:          model.goPrev(); return true                   // page up
        case 121:          advance(); return true                        // page down
        case 115:          model.goFirst(); return true                  // home
        case 119:          model.goLast(); return true                   // end
        case 53:           handleEscape(); return true                   // esc
        case 48:           model.showOverview.toggle(); return true      // tab
        case 36:                                                          // return
            if gotoBuffer.isEmpty { advance() } else { jumpToBuffer() }
            return true
        default:           break
        }

        switch ch {
        case "b": model.toggleBlack(); return true
        case "w": model.toggleWhite(); return true
        case "f": toggleAudienceFullscreen(); return true
        case "g": model.showOverview.toggle(); return true
        case "l": model.tool = (model.tool == .laser ? .off : .laser); return true
        case "d": model.tool = (model.tool == .pen ? .off : .pen); return true
        case "c": model.clearAnnotations(); return true
        case "p": model.toggleTimer(); return true
        case "r": model.resetTimer(); return true
        case "e": model.cyclePreset(); return true
        case "m": cycleAudienceDisplay(); return true
        default:
            if ch.count == 1, Int(ch) != nil { gotoBuffer += ch; return true }
        }
        return false
    }

    private func jumpToBuffer() {
        if let n = Int(gotoBuffer) { model.goTo(n - 1) }
        gotoBuffer = ""
    }

    private func handleEscape() {
        if audienceCovering { toggleAudienceFullscreen() }
        else if model.blank != .none { model.blank = .none }
        else if model.tool != .off { model.tool = .off }
        gotoBuffer = ""
    }

    // MARK: Menu

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About PDF Presenter",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PDF Presenter",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let open = NSMenuItem(title: "Open…", action: #selector(openDocumentAction(_:)), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        // View
        let viewItem = NSMenuItem(); mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        for (i, p) in LayoutPreset.allCases.enumerated() {
            let it = NSMenuItem(title: "Layout: \(p.title)", action: #selector(setPreset(_:)), keyEquivalent: "\(i + 1)")
            it.target = self; it.representedObject = p.rawValue
            viewMenu.addItem(it)
        }
        viewMenu.addItem(.separator())
        let notesAuto = NSMenuItem(title: "Notes: Auto-detect", action: #selector(setSplitAuto(_:)), keyEquivalent: "")
        notesAuto.target = self; viewMenu.addItem(notesAuto)
        let notesSplit = NSMenuItem(title: "Notes: Split (Beamer)", action: #selector(setSplitOn(_:)), keyEquivalent: "")
        notesSplit.target = self; viewMenu.addItem(notesSplit)
        let notesNone = NSMenuItem(title: "Notes: None", action: #selector(setSplitOff(_:)), keyEquivalent: "")
        notesNone.target = self; viewMenu.addItem(notesNone)
        viewMenu.addItem(.separator())
        let overview = NSMenuItem(title: "Slide Overview", action: #selector(toggleOverview(_:)), keyEquivalent: "g")
        overview.keyEquivalentModifierMask = [.command]; overview.target = self
        viewMenu.addItem(overview)
        viewItem.submenu = viewMenu

        // Present
        let presentItem = NSMenuItem(); mainMenu.addItem(presentItem)
        let presentMenu = NSMenu(title: "Present")
        let pres = NSMenuItem(title: "Present on External Display",
                              action: #selector(presentAction(_:)), keyEquivalent: "\r")
        pres.target = self; presentMenu.addItem(pres)
        let full = NSMenuItem(title: "Toggle Audience Full-Screen",
                              action: #selector(fullscreenAction(_:)), keyEquivalent: "f")
        full.target = self; presentMenu.addItem(full)
        presentMenu.addItem(.separator())
        let dm = NSMenu(title: "Audience Display")
        let dmItem = NSMenuItem(title: "Audience Display", action: nil, keyEquivalent: "")
        dmItem.submenu = dm
        presentMenu.addItem(dmItem)
        displayMenu = dm
        presentItem.submenu = presentMenu

        NSApp.mainMenu = mainMenu
        rebuildDisplayMenu()
    }

    private func rebuildDisplayMenu() {
        guard let dm = displayMenu else { return }
        dm.removeAllItems()
        let auto = NSMenuItem(title: "Automatic", action: #selector(chooseAuto(_:)), keyEquivalent: "")
        auto.target = self
        auto.state = (audienceScreenChoice == nil) ? .on : .off
        dm.addItem(auto)
        let presScreen = presenterScreen()
        let chosen = audienceScreen(excluding: presScreen).map { displayID($0) }
        for s in NSScreen.screens where s != presScreen {
            let id = displayID(s)
            let w = Int(s.frame.width), h = Int(s.frame.height)
            let kind = isBuiltin(s) ? "Built-in" : "External"
            let it = NSMenuItem(title: "\(kind) \(w)×\(h)", action: #selector(chooseDisplay(_:)), keyEquivalent: "")
            it.target = self
            it.tag = Int(id)
            it.state = (audienceScreenChoice == nil ? (id == chosen) : (id == audienceScreenChoice)) ? .on : .off
            dm.addItem(it)
        }
        if dm.items.count == 1 {
            dm.addItem(.separator())
            let none = NSMenuItem(title: "(no external display)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            dm.addItem(none)
        }
    }

    @objc private func setPreset(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let p = LayoutPreset(rawValue: raw) { model.preset = p }
    }
    @objc private func setSplitAuto(_ s: Any?) { model.splitMode = .auto }
    @objc private func setSplitOn(_ s: Any?)   { model.splitMode = .splitRight }
    @objc private func setSplitOff(_ s: Any?)  { model.splitMode = .single }
    @objc private func toggleOverview(_ s: Any?) { model.showOverview.toggle() }
    @objc private func presentAction(_ s: Any?)    { arrangeWindows(present: true) }
    @objc private func fullscreenAction(_ s: Any?) { toggleAudienceFullscreen() }
    @objc private func chooseAuto(_ s: Any?) { audienceScreenChoice = nil; arrangeWindows() }
    @objc private func chooseDisplay(_ sender: NSMenuItem) {
        audienceScreenChoice = CGDirectDisplayID(sender.tag); arrangeWindows()
    }

    // MARK: Snapshot mode (offscreen render for verification)

    private func runSnapshotMode() {
        let args = CommandLine.arguments
        let outDir = args.firstIndex(of: "--snapshot").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "/tmp"
        if let pdf = args.first(where: { $0.lowercased().hasSuffix(".pdf") }) {
            model.load(url: URL(fileURLWithPath: pdf))
        }
        if let p = model.currentPage {
            let b = p.bounds(for: .cropBox)
            let notes = model.notesRegion(for: p).map { "\($0)" } ?? "nil"
            print("DIAG detectedSplit=\(model.detectedSplit) isSplit=\(model.isSplit) "
                + "cropBox=\(b.size) slideRegion=\(model.slideRegion(for: p)) notesRegion=\(notes) "
                + "slideAspect=\(String(format: "%.3f", model.slideAspect))")
        } else {
            print("DIAG no document loaded")
        }
        for preset in LayoutPreset.allCases {
            model.preset = preset
            writeSnapshot(PresenterView(model: model), size: CGSize(width: 1512, height: 900),
                          to: "\(outDir)/presenter-\(preset.rawValue).png")
        }
        writeSnapshot(AudienceView(model: model), size: CGSize(width: 1920, height: 1080),
                      to: "\(outDir)/audience.png")
        print("SNAPSHOTS WRITTEN to \(outDir)")
        NSApp.terminate(nil)
    }

    private func writeSnapshot<V: View>(_ view: V, size: CGSize, to path: String) {
        MainActor.assumeIsolated {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 2
            guard let img = renderer.nsImage,
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("snapshot FAILED: \(path)"); return
            }
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
