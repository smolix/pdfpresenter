// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import AppKit
import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers
import PresenterKit

/// Borderless windows refuse key status by default; allow it so the audience
/// cover can still receive events if needed.
final class SlideWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = PresentationModel()

    private var presenterWindow: NSWindow!
    private var audienceWindow: NSWindow!         // decorated, movable, minimizable
    private var coverWindow: SlideWindow!         // dedicated borderless cover; never restyled live
    private var keyMonitor: Any?
    private var audiencePresenting = false        // is the cover window currently shown?
    private var gotoBuffer = ""
    private var pendingURL: URL?
    private var audienceScreenChoice: CGDirectDisplayID?    // user override; nil = automatic
    private var presenterScreenChoice: CGDirectDisplayID?   // user override; nil = automatic (built-in)
    private var audienceDisplayMenu: NSMenu?
    private var presenterDisplayMenu: NSMenu?
    private var openRecentMenu: NSMenu?
    private var arrangeWork: DispatchWorkItem?      // coalesces screen-parameter bursts
    private lazy var docWatcher = DocumentWatcher { [weak self] in self?.reloadDocument() }
    private let wakeGuard = WakeGuard()             // holds the display awake while presenting

    private var recentFiles: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentFiles") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "recentFiles") }
    }

    // iOS companion (PDF Presenter for iPhone / iPad) over Multipeer.
    private var remoteServer: RemoteServer!
    let remoteStatus = RemoteStatus()
    private var remoteWindow: NSWindow?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--snapshot") {
            runSnapshotMode()
            return
        }

        model.loadSettings()
        if UserDefaults.standard.object(forKey: "autoReload") != nil {
            docWatcher.isEnabled = UserDefaults.standard.bool(forKey: "autoReload")   // default on
        }
        setupMenu()
        setupWindows()
        // Start windowed on one screen — don't auto-cover an external display.
        // The user presents when ready (F / green zoom / Present menu).
        audiencePresenting = false
        arrangeWindows()
        installKeyMonitor()
        startRemoteServer()
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
            cycleDisplay: { [weak self] in self?.cycleAudienceDisplay() },
            exportAnnotated: { [weak self] in self?.exportAnnotatedPDF() }
        )

        let presenter = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        presenter.title = "Presenter"
        presenter.isReleasedWhenClosed = false   // ARC owns it; closing must not deallocate
        presenter.contentView = NSHostingView(rootView: PresenterView(model: model, actions: actions))
        presenter.center()
        presenter.setFrameAutosaveName("PresenterWindow")
        presenterWindow = presenter

        // The windowed audience: a normal, decorated window you can drag between
        // displays, minimize, and zoom. We never restyle it live (that blanks an
        // NSHostingView); full-screen is the separate borderless cover below.
        let audience = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        audience.title = "Audience"
        audience.isReleasedWhenClosed = false    // ARC owns it; closing must not deallocate
        audience.backgroundColor = .black
        audience.collectionBehavior = [.fullScreenNone]   // green button → zoom, which we intercept
        audience.delegate = self
        audience.contentView = NSHostingView(rootView: AudienceView(model: model))
        audienceWindow = audience

        // The cover: a borderless full-screen window with its OWN hosting view,
        // shown/hidden but never restyled, so it can't go black mid-present.
        let cover = SlideWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.borderless], backing: .buffered, defer: false)
        cover.isReleasedWhenClosed = false
        cover.backgroundColor = .black
        cover.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        // Pin the cover to ITS display's space. Deliberately no .canJoinAllSpaces:
        // an above-everything window that roams every space ping-pongs for focus
        // with a full-screen app on another display. Keynote likewise keeps its
        // slideshow on one screen; .fullScreenAuxiliary still lets the cover sit
        // over a full-screen window on its own display.
        cover.collectionBehavior = [.stationary, .fullScreenAuxiliary]
        cover.contentView = NSHostingView(rootView: AudienceView(model: model))
        coverWindow = cover

        presenter.makeKeyAndOrderFront(nil)
        audience.orderFront(nil)
    }

    // MARK: Display routing (no hardcoded display count)

    private func displayID(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    private func isBuiltin(_ s: NSScreen) -> Bool { CGDisplayIsBuiltin(displayID(s)) != 0 }

    /// Screen that should hold the presenter view. Honors a user override, else
    /// the built-in panel if there is one, else the current main screen.
    private func presenterScreen() -> NSScreen {
        if let id = presenterScreenChoice,
           let s = NSScreen.screens.first(where: { displayID($0) == id }) { return s }
        return NSScreen.screens.first(where: isBuiltin) ?? NSScreen.main ?? NSScreen.screens[0]
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

    /// The screen the cover should land on when presenting: an explicit audience
    /// choice, else wherever the user dragged the windowed audience (so the green
    /// button / F follow it), else the automatic external, else the only screen.
    private func resolveAudienceScreen() -> NSScreen {
        let pres = presenterScreen()
        if let id = audienceScreenChoice,
           let s = NSScreen.screens.first(where: { displayID($0) == id && $0 != pres }) { return s }
        if audienceScreenChoice == nil, let s = audienceWindow.screen, s != pres { return s }
        if let s = audienceScreen(excluding: pres) { return s }
        return pres   // single display: the cover takes over the only screen
    }

    /// Screen-parameter changes arrive in bursts — a display plugged in, but also
    /// ANY display (or app) entering/leaving full screen, which shifts a menu bar
    /// or visibleFrame. Coalesce the burst and re-lay-out *passively*, so we never
    /// yank key focus back to the presenter and start a war with that full-screen
    /// app (the "two displays alternating for attention" bug).
    @objc private func screensChanged() {
        arrangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.arrangeWindows(activate: false) }
        arrangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Re-lays out both windows for the current display configuration. Idempotent.
    /// `activate` raises and keys the presenter (user-driven layout); pass `false`
    /// for passive re-layouts (screen-parameter changes) so focus stays put.
    private func arrangeWindows(activate: Bool = true) {
        guard presenterWindow != nil, audienceWindow != nil, coverWindow != nil else { return }
        let presScreen = presenterScreen()
        presenterWindow.setFrame(presScreen.visibleFrame, display: true)
        if activate { presenterWindow.makeKeyAndOrderFront(nil) } else { presenterWindow.orderFront(nil) }

        if audiencePresenting {
            showCover(on: resolveAudienceScreen(), activate: activate)
        } else {
            hideCover()
            placeWindowedAudience(on: audienceScreen(excluding: presScreen), activate: activate)
        }
        rebuildDisplayMenus()
    }

    /// Shows the borderless cover on `screen` and tucks the windowed audience
    /// away so there's just one audience surface. `activate` re-keys the presenter
    /// (skip it on passive re-layouts so we don't steal focus).
    private func showCover(on screen: NSScreen, activate: Bool = true) {
        coverWindow.setFrame(screen.frame, display: true)
        coverWindow.orderFrontRegardless()
        audienceWindow.orderOut(nil)
        audiencePresenting = true
        wakeGuard.setPresenting(true)   // no screensaver / display sleep while presenting
        if activate { presenterWindow.makeKeyAndOrderFront(nil) }
    }

    private func hideCover() {
        coverWindow.orderOut(nil)
        audiencePresenting = false
        wakeGuard.setPresenting(false)   // let the display sleep normally again
    }

    /// Positions the windowed audience on `screen`. By default it won't fight a
    /// manual drag (only repositions a hidden/placeless window); `force` moves it
    /// regardless — used when the user explicitly retargets via M / the menu.
    private func placeWindowedAudience(on screen: NSScreen?, force: Bool = false, activate: Bool = true) {
        let s = screen ?? presenterScreen()
        if force || !audienceWindow.isVisible || audienceWindow.screen == nil {
            audienceWindow.setFrame(
                NSRect(x: s.visibleFrame.minX + 40, y: s.visibleFrame.minY + 40, width: 960, height: 540),
                display: true)
        }
        audienceWindow.orderFront(nil)
        if activate { presenterWindow.makeKeyAndOrderFront(nil) }
    }

    /// Begin presenting full-screen. `screen` nil resolves automatically.
    private func presentAudience(on screen: NSScreen? = nil) {
        showCover(on: screen ?? resolveAudienceScreen())
        rebuildDisplayMenus()
    }

    private func toggleAudienceFullscreen() {
        if audiencePresenting {
            hideCover()
            placeWindowedAudience(on: audienceScreen(excluding: presenterScreen()))
        } else {
            presentAudience()
        }
        rebuildDisplayMenus()
    }

    private func cycleAudienceDisplay() {
        let pres = presenterScreen()
        let others = NSScreen.screens.filter { $0 != pres }
        guard others.count > 1 else { NSSound.beep(); return }
        let ids = others.map { displayID($0) }

        // Advance from where the audience is *actually* showing right now (the
        // cover's screen when presenting, else the windowed audience's screen),
        // so the first press already moves instead of just catching up to a
        // stale computed choice.
        let actualScreen = audiencePresenting ? coverWindow.screen : audienceWindow.screen
        let current = actualScreen.map { displayID($0) }
            ?? audienceScreenChoice
            ?? audienceScreen(excluding: pres).map { displayID($0) }
        if let cur = current, let i = ids.firstIndex(of: cur) {
            audienceScreenChoice = ids[(i + 1) % ids.count]
        } else {
            audienceScreenChoice = ids.first
        }

        guard let target = others.first(where: { displayID($0) == audienceScreenChoice }) else { return }
        if audiencePresenting {
            showCover(on: target)
        } else {
            placeWindowedAudience(on: target, force: true)
        }
        rebuildDisplayMenus()
    }

    /// Swap which display is presenter and which is audience, pinning both to an
    /// explicit choice so the assignment sticks.
    private func swapDisplays() {
        let pres = presenterScreen()
        guard let aud = audienceScreen(excluding: pres) else { NSSound.beep(); return }
        let presID = displayID(pres), audID = displayID(aud)
        presenterScreenChoice = audID
        audienceScreenChoice = presID
        arrangeWindows()
    }

    // MARK: Window delegate — green "zoom" button presents instead of zooming

    /// Intercept the windowed audience's green button so it covers the display
    /// it's currently on (native zoom on a hosting view tends to blank out).
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard window == audienceWindow else { return true }
        presentAudience(on: window.screen)
        return false
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
        addRecent(url)
        docWatcher.watch(url)   // hot-reload when the file is rebuilt on disk
    }

    /// Fired by the watcher once the file on disk has settled after a rebuild.
    private func reloadDocument() {
        if model.reload() {
            docWatcher.markLoaded()
            presenterWindow?.title = "Presenter — " + (model.documentURL?.lastPathComponent ?? "")
        }
    }

    @objc private func toggleAutoReload(_ sender: NSMenuItem) {
        docWatcher.isEnabled.toggle()
        UserDefaults.standard.set(docWatcher.isEnabled, forKey: "autoReload")
        sender.state = docWatcher.isEnabled ? .on : .off
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

        if model.showHelp {
            if code == 53 || ch == "?" { model.showHelp = false }   // esc or ?
            return true                                             // swallow keys while help is up
        }

        // Control combos: only ⌃M (move audience to next display). A modified key
        // is much harder to hit by accident mid-talk than a bare M; ignore any
        // other control-letter so it can't fire a single-key action.
        if e.modifierFlags.contains(.control) {
            if code == 46 { cycleAudienceDisplay(); return true }   // ⌃M
            return false
        }

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
        case "h": model.tool = (model.tool == .highlighter ? .off : .highlighter); return true
        case "s": model.tool = (model.tool == .spotlight ? .off : .spotlight); return true
        case "x": model.tool = (model.tool == .eraser ? .off : .eraser); return true
        case "z": model.magnify.toggle(); return true
        case "c": model.clearAnnotations(); return true
        case "p": model.toggleTimer(); return true
        case "r": model.resetTimer(); return true
        case "e": model.cyclePreset(); return true
        case "?": model.showHelp = true; return true
        default:
            if ch.count == 1, Int(ch) != nil { gotoBuffer += ch; return true }
        }
        return false
    }

    private func jumpToBuffer() {
        // Resolve the typed number against the document's page labels (the numbers
        // printed on the slides); fall back to the raw index, then beep.
        if !model.goToLabel(gotoBuffer) {
            if let n = Int(gotoBuffer), n >= 1, n <= model.pageCount { model.goTo(n - 1) }
            else { NSSound.beep() }
        }
        gotoBuffer = ""
    }

    private func handleEscape() {
        if audiencePresenting { toggleAudienceFullscreen() }
        else if model.blank != .none { model.blank = .none }
        else if model.magnify { model.magnify = false }
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
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentItem.submenu = recentMenu
        openRecentMenu = recentMenu
        fileMenu.addItem(recentItem)
        let export = NSMenuItem(title: "Export Annotated PDF…", action: #selector(exportAction(_:)), keyEquivalent: "e")
        export.target = self
        fileMenu.addItem(export)
        fileMenu.addItem(.separator())
        let autoReload = NSMenuItem(title: "Auto-Reload on Change",
                                    action: #selector(toggleAutoReload(_:)), keyEquivalent: "")
        autoReload.target = self
        autoReload.state = docWatcher.isEnabled ? .on : .off
        fileMenu.addItem(autoReload)
        fileMenu.addItem(.separator())
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
        let full = NSMenuItem(title: "Toggle Audience Full-Screen",
                              action: #selector(fullscreenAction(_:)), keyEquivalent: "f")
        full.target = self; presentMenu.addItem(full)
        presentMenu.addItem(.separator())

        let move = NSMenuItem(title: "Move Audience to Next Display",
                              action: #selector(cycleAudienceAction(_:)), keyEquivalent: "m")
        move.keyEquivalentModifierMask = [.control]; move.target = self
        presentMenu.addItem(move)
        presentMenu.addItem(.separator())

        let pdm = NSMenu(title: "Presenter Display")
        let pdmItem = NSMenuItem(title: "Presenter Display", action: nil, keyEquivalent: "")
        pdmItem.submenu = pdm
        presentMenu.addItem(pdmItem)
        presenterDisplayMenu = pdm

        let adm = NSMenu(title: "Audience Display")
        let admItem = NSMenuItem(title: "Audience Display", action: nil, keyEquivalent: "")
        admItem.submenu = adm
        presentMenu.addItem(admItem)
        audienceDisplayMenu = adm

        let swap = NSMenuItem(title: "Swap Presenter / Audience Displays",
                              action: #selector(swapAction(_:)), keyEquivalent: "")
        swap.target = self; presentMenu.addItem(swap)
        presentItem.submenu = presentMenu

        // Remote (iOS companion)
        let remoteItem = NSMenuItem(); mainMenu.addItem(remoteItem)
        let remoteMenu = NSMenu(title: "Remote")
        let pairing = NSMenuItem(title: "Pairing & Status…", action: #selector(showRemotePanel(_:)), keyEquivalent: "r")
        pairing.keyEquivalentModifierMask = [.command, .shift]; pairing.target = self
        remoteMenu.addItem(pairing)
        remoteMenu.addItem(.separator())
        let regen = NSMenuItem(title: "Regenerate Pairing Code", action: #selector(regenerateCodeAction(_:)), keyEquivalent: "")
        regen.target = self; remoteMenu.addItem(regen)
        let forget = NSMenuItem(title: "Forget Paired Devices", action: #selector(forgetDevicesAction(_:)), keyEquivalent: "")
        forget.target = self; remoteMenu.addItem(forget)
        remoteItem.submenu = remoteMenu

        // Help
        let helpItem = NSMenuItem(); mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        let shortcuts = NSMenuItem(title: "Keyboard Shortcuts",
                                   action: #selector(showShortcuts(_:)), keyEquivalent: "?")
        shortcuts.keyEquivalentModifierMask = [.command]; shortcuts.target = self
        helpMenu.addItem(shortcuts)
        helpItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
        rebuildDisplayMenus()
        rebuildRecentMenu()
    }

    // MARK: Recent files

    private func addRecent(_ url: URL) {
        var list = recentFiles
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        recentFiles = Array(list.prefix(10))
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        guard let m = openRecentMenu else { return }
        m.removeAllItems()
        let existing = recentFiles.filter { FileManager.default.fileExists(atPath: $0) }
        if existing != recentFiles { recentFiles = existing }   // prune moved/deleted
        if existing.isEmpty {
            let none = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            none.isEnabled = false
            m.addItem(none)
            return
        }
        for path in existing {
            let it = NSMenuItem(title: (path as NSString).lastPathComponent,
                                action: #selector(openRecentAction(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = path; it.toolTip = path
            m.addItem(it)
        }
        m.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentsAction(_:)), keyEquivalent: "")
        clear.target = self
        m.addItem(clear)
    }

    @objc private func openRecentAction(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openURL(URL(fileURLWithPath: path)) }
    }
    @objc private func clearRecentsAction(_ s: Any?) { recentFiles = []; rebuildRecentMenu() }

    private func rebuildDisplayMenus() {
        let presScreen = presenterScreen()
        let audChosen = audienceScreen(excluding: presScreen).map { displayID($0) }

        // Audience: Automatic + every display that isn't the presenter's.
        if let adm = audienceDisplayMenu {
            adm.removeAllItems()
            let auto = NSMenuItem(title: "Automatic", action: #selector(chooseAudienceAuto(_:)), keyEquivalent: "")
            auto.target = self
            auto.state = (audienceScreenChoice == nil) ? .on : .off
            adm.addItem(auto)
            for s in NSScreen.screens where s != presScreen {
                let id = displayID(s)
                let it = NSMenuItem(title: displayLabel(s), action: #selector(chooseAudienceDisplay(_:)), keyEquivalent: "")
                it.target = self
                it.tag = Int(id)
                it.state = (audienceScreenChoice == nil ? (id == audChosen) : (id == audienceScreenChoice)) ? .on : .off
                adm.addItem(it)
            }
            if adm.items.count == 1 {
                adm.addItem(.separator())
                let none = NSMenuItem(title: "(no external display)", action: nil, keyEquivalent: "")
                none.isEnabled = false
                adm.addItem(none)
            }
        }

        // Presenter: Automatic + every display.
        if let pdm = presenterDisplayMenu {
            pdm.removeAllItems()
            let auto = NSMenuItem(title: "Automatic (built-in)", action: #selector(choosePresenterAuto(_:)), keyEquivalent: "")
            auto.target = self
            auto.state = (presenterScreenChoice == nil) ? .on : .off
            pdm.addItem(auto)
            let curPres = displayID(presScreen)
            for s in NSScreen.screens {
                let id = displayID(s)
                let it = NSMenuItem(title: displayLabel(s), action: #selector(choosePresenterDisplay(_:)), keyEquivalent: "")
                it.target = self
                it.tag = Int(id)
                it.state = (presenterScreenChoice == nil ? (id == curPres) : (id == presenterScreenChoice)) ? .on : .off
                pdm.addItem(it)
            }
        }
    }

    private func displayLabel(_ s: NSScreen) -> String {
        let w = Int(s.frame.width), h = Int(s.frame.height)
        // Prefer the real display name (e.g. "DELL U2720Q") so two identical-size
        // externals are still distinguishable; fall back to a generic label.
        let name = s.localizedName
        if !name.isEmpty { return "\(name) (\(w)×\(h))" }
        return "\(isBuiltin(s) ? "Built-in" : "External") \(w)×\(h)"
    }

    @objc private func setPreset(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let p = LayoutPreset(rawValue: raw) { model.preset = p }
    }
    @objc private func setSplitAuto(_ s: Any?) { model.splitMode = .auto }
    @objc private func setSplitOn(_ s: Any?)   { model.splitMode = .splitRight }
    @objc private func setSplitOff(_ s: Any?)  { model.splitMode = .single }
    @objc private func toggleOverview(_ s: Any?) { model.showOverview.toggle() }
    @objc private func fullscreenAction(_ s: Any?) { toggleAudienceFullscreen() }
    @objc private func cycleAudienceAction(_ s: Any?) { cycleAudienceDisplay() }
    @objc private func chooseAudienceAuto(_ s: Any?) { audienceScreenChoice = nil; arrangeWindows() }
    @objc private func chooseAudienceDisplay(_ sender: NSMenuItem) {
        audienceScreenChoice = CGDirectDisplayID(sender.tag)
        if presenterScreenChoice == audienceScreenChoice { presenterScreenChoice = nil }
        arrangeWindows()
    }
    @objc private func choosePresenterAuto(_ s: Any?) { presenterScreenChoice = nil; arrangeWindows() }
    @objc private func choosePresenterDisplay(_ sender: NSMenuItem) {
        presenterScreenChoice = CGDirectDisplayID(sender.tag)
        if audienceScreenChoice == presenterScreenChoice { audienceScreenChoice = nil }
        arrangeWindows()
    }
    @objc private func swapAction(_ s: Any?) { swapDisplays() }
    @objc private func showShortcuts(_ s: Any?) { model.showHelp = true }

    // MARK: Remote (iOS companion)

    private func startRemoteServer() {
        let macName = Host.current().localizedName ?? "Mac"
        let server = RemoteServer(model: model, displayName: macName)
        server.onToggleFullscreen = { [weak self] in self?.toggleAudienceFullscreen() }
        server.onCycleDisplay = { [weak self] in self?.cycleAudienceDisplay() }
        server.externalDisplays = { [weak self] in
            guard let self else { return 0 }
            return NSScreen.screens.filter { $0 != self.presenterScreen() }.count
        }
        server.isPresenting = { [weak self] in self?.audiencePresenting ?? false }
        server.onStatusChange = { [weak self] in self?.refreshRemoteStatus() }
        remoteServer = server
        server.start()
        refreshRemoteStatus()
    }

    private func refreshRemoteStatus() {
        guard let server = remoteServer else { return }
        remoteStatus.code = server.pairingCode
        remoteStatus.connected = server.connectedCount
        remoteStatus.pairedDevices = server.pairedNames
        remoteStatus.advertising = true
    }

    @objc private func showRemotePanel(_ s: Any?) {
        if remoteWindow == nil {
            let panel = RemotePanel(
                status: remoteStatus,
                onRegenerate: { [weak self] in self?.remoteServer?.regenerateCode() },
                onForget: { [weak self] in self?.remoteServer?.forgetDevices() })
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = "Remote Control"
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: panel)
            win.center()
            remoteWindow = win
        }
        remoteWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func regenerateCodeAction(_ s: Any?) { remoteServer?.regenerateCode(); showRemotePanel(nil) }
    @objc private func forgetDevicesAction(_ s: Any?) { remoteServer?.forgetDevices() }

    // MARK: Export annotated PDF

    @objc private func exportAction(_ sender: Any?) { exportAnnotatedPDF() }

    private func exportAnnotatedPDF() {
        guard let doc = model.document, model.pageCount > 0,
              let firstPage = doc.page(at: 0) else { NSSound.beep(); return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue =
            (model.documentURL?.deletingPathExtension().lastPathComponent ?? "slides") + "-annotated.pdf"
        guard panel.runModal() == .OK, let outURL = panel.url else { return }

        var mediaBox = CGRect(origin: .zero, size: model.slideRegion(for: firstPage).size)
        guard let ctx = CGContext(outURL as CFURL, mediaBox: &mediaBox, nil) else { NSSound.beep(); return }
        let pageSize = mediaBox.size

        for i in 0..<model.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let region = model.slideRegion(for: page)
            ctx.beginPDFPage(nil)

            // Burn the slide bitmap, then the strokes (normalized y-down -> PDF y-up).
            let img = SlideRenderer.shared.image(page: page, region: region,
                                                 key: "export-\(i)", pixelWidth: max(1600, region.width * 2))
            if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cg, in: CGRect(origin: .zero, size: pageSize))
            }
            for s in (model.strokes[i] ?? []) where s.points.count > 1 {
                let base = annotationNSColors[annotationColorIndex(s.colorIndex)]
                ctx.setStrokeColor((s.highlighter ? base.withAlphaComponent(0.35) : base).cgColor)
                ctx.setLineWidth(max(1, s.width * pageSize.width))
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                ctx.beginPath()
                for (j, p) in s.points.enumerated() {
                    let pt = CGPoint(x: p.x * pageSize.width, y: (1 - p.y) * pageSize.height)
                    if j == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
                }
                ctx.strokePath()
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        NSWorkspace.shared.open(outURL)
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
                + "slideAspect=\(String(format: "%.3f", model.slideAspect)) "
                + "sidecarNotes=\(model.notesSidecar.count)")
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

        if ProcessInfo.processInfo.environment["DEMO"] != nil {
            // Countdown: 20-min talk, 18:00 elapsed -> 2:00 left (amber).
            model.talkLength = 20 * 60
            model.accumulated = 18 * 60
            // Red pen + yellow highlighter on the current slide.
            model.strokes[0] = [
                Stroke(points: (0...24).map { CGPoint(x: 0.26 + Double($0) * 0.013,
                                                      y: 0.56 + sin(Double($0) * 0.45) * 0.05) },
                       width: 0.006, colorIndex: 0, highlighter: false),
                Stroke(points: (0...20).map { CGPoint(x: 0.27 + Double($0) * 0.015, y: 0.72) },
                       width: 0.022, colorIndex: 3, highlighter: true),
            ]
            model.preset = .notesRight
            writeSnapshot(PresenterView(model: model), size: CGSize(width: 1512, height: 900),
                          to: "\(outDir)/demo-annotations-countdown.png")
            model.tool = .spotlight; model.pointer = CGPoint(x: 0.5, y: 0.45)
            writeSnapshot(AudienceView(model: model), size: CGSize(width: 1920, height: 1080),
                          to: "\(outDir)/demo-spotlight.png")
            model.tool = .off; model.magnify = true; model.pointer = CGPoint(x: 0.5, y: 0.5)
            writeSnapshot(AudienceView(model: model), size: CGSize(width: 1920, height: 1080),
                          to: "\(outDir)/demo-zoom.png")
            model.magnify = false; model.pointer = nil
            print("DEMO snapshots written")
        }

        if ProcessInfo.processInfo.environment["SPLITSWEEP"] != nil {
            for (name, mode) in [("auto", SplitMode.auto), ("split", SplitMode.splitRight), ("single", SplitMode.single)] {
                model.splitMode = mode
                print("SPLIT \(name): isSplit=\(model.isSplit) slideAspect=\(String(format: "%.2f", model.slideAspect))")
                writeSnapshot(AudienceView(model: model), size: CGSize(width: 1920, height: 1080),
                              to: "\(outDir)/split-\(name).png")
            }
            model.splitMode = .auto
        }

        if let reload = ProcessInfo.processInfo.environment["RELOAD"] {
            model.load(url: URL(fileURLWithPath: reload))
            print("RELOAD pageCount=\(model.pageCount) isSplit=\(model.isSplit)")
            writeSnapshot(AudienceView(model: model), size: CGSize(width: 1920, height: 1080),
                          to: "\(outDir)/reload.png")
        }

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
