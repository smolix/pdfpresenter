// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import AppKit
import CoreGraphics
import PresenterKit

/// Hosts the Multipeer service the iOS companion connects to. Applies incoming
/// control / pointer / stroke messages to the shared `PresentationModel`, and
/// streams back a `PresenterState` snapshot plus current/next/notes slide JPEGs
/// so the phone or iPad mirrors the desktop presenter. Control is gated behind a
/// one-time pairing code; trusted devices reconnect silently afterward.
final class RemoteServer: NSObject, PeerLinkDelegate {
    private let model: PresentationModel
    private let link: PeerLink

    private(set) var pairingCode: String
    private var trusted: Set<String>           // persisted device names
    private(set) var pairedDevices: Set<String> = []

    // App-level actions the model can't perform on its own.
    var onToggleFullscreen: () -> Void = {}
    var onCycleDisplay: () -> Void = {}
    var externalDisplays: () -> Int = { 0 }
    var isPresenting: () -> Bool = { false }
    /// Notified (on main) when connection or pairing status changes, for the UI.
    var onStatusChange: () -> Void = {}

    private var pushTimer: Timer?
    private var lastState: PresenterState?
    private var lastThumbIndex = -1
    private var lastThumbToken = -1
    private var lastStrokesSig = ""

    private static let trustedKey = "remoteTrustedDevices"

    init(model: PresentationModel, displayName: String) {
        self.model = model
        self.link = PeerLink(role: .host, displayName: displayName)
        self.trusted = Set(UserDefaults.standard.stringArray(forKey: Self.trustedKey) ?? [])
        self.pairingCode = Self.newCode()
        super.init()
        link.delegate = self
    }

    var connectedCount: Int { link.connectedDevices.count }
    var pairedCount: Int { pairedDevices.count }
    var pairedNames: [String] { pairedDevices.sorted() }

    func start() {
        link.start()
        pushTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pushIfNeeded()
        }
    }
    func stop() { pushTimer?.invalidate(); pushTimer = nil; link.stop() }

    func regenerateCode() { pairingCode = Self.newCode(); onStatusChange() }
    func forgetDevices() {
        trusted.removeAll(); pairedDevices.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.trustedKey)
        onStatusChange()
    }

    private static func newCode() -> String { String(format: "%06d", Int.random(in: 0..<1_000_000)) }

    // MARK: PeerLinkDelegate

    func peerLinkConnectionChanged(_ link: PeerLink) {
        pairedDevices.formIntersection(Set(link.connectedDevices))   // drop departed peers
        onStatusChange()
    }

    func peerLink(_ link: PeerLink, didReceive message: PresenterMessage, from device: String) {
        if case .pair(let code, let dev) = message {
            let ok = (code == pairingCode) || trusted.contains(dev)
            if ok {
                trusted.insert(dev)
                UserDefaults.standard.set(Array(trusted), forKey: Self.trustedKey)
                pairedDevices.insert(device)
                link.send(.paired(ok: true, reason: nil), to: [device])
                sendFullSync(to: [device])
                onStatusChange()
            } else {
                link.send(.paired(ok: false, reason: "Wrong code"), to: [device])
            }
            return
        }
        guard pairedDevices.contains(device) else { return }   // ignore control until paired
        apply(message)
    }

    private func apply(_ message: PresenterMessage) {
        switch message {
        case .command(let cmd):     applyCommand(cmd)
        case .pointer(let p):       model.pointer = p
        case .strokeBegin(let s):   model.liveStroke = s
        case .strokeExtend(let p):  model.liveStroke?.points.append(p)
        case .strokeEnd:            model.commitStroke()
        case .erase(let p):         model.eraseAt(p)
        case .requestThumbnails:    sendFullSync(to: Array(pairedDevices))
        default:                    break
        }
    }

    private func applyCommand(_ cmd: RemoteCommand) {
        switch cmd {
        case .next:               model.startTimerIfNeeded(); model.goNext()
        case .prev:               model.goPrev()
        case .first:              model.goFirst()
        case .last:               model.goLast()
        case .goToIndex(let i):   model.goTo(i)
        case .goToLabel(let s):   _ = model.goToLabel(s)
        case .toggleBlack:        model.toggleBlack()
        case .toggleWhite:        model.toggleWhite()
        case .toggleTimer:        model.toggleTimer()
        case .resetTimer:         model.resetTimer()
        case .cyclePreset:        model.cyclePreset()
        case .setPreset(let p):   model.preset = p
        case .setSplitMode(let m): model.splitMode = m
        case .toggleFullscreen:   onToggleFullscreen()
        case .cycleDisplay:       onCycleDisplay()
        case .setTool(let t):     model.tool = t
        case .clearAnnotations:   model.clearAnnotations()
        case .setMagnify(let on): model.magnify = on
        case .setPenColor(let i): model.penColorIndex = annotationPaletteIndex(i)
        case .setTalkLength(let t): model.talkLength = t
        }
    }

    // MARK: Push state / thumbnails / strokes

    private func pushIfNeeded() {
        guard !pairedDevices.isEmpty else { return }
        let targets = Array(pairedDevices)

        let s = buildState()
        if s != lastState { lastState = s; link.send(.state(s), to: targets) }

        if model.currentIndex != lastThumbIndex || model.docToken != lastThumbToken {
            lastThumbIndex = model.currentIndex; lastThumbToken = model.docToken
            sendThumbnails(to: targets)
            lastStrokesSig = strokesSignature()
            sendStrokes(to: targets)
        } else {
            let sig = strokesSignature()
            if sig != lastStrokesSig { lastStrokesSig = sig; sendStrokes(to: targets) }
        }
    }

    private func buildState() -> PresenterState {
        PresenterState(
            docToken: model.docToken,
            documentName: model.documentURL?.lastPathComponent ?? "",
            pageCount: model.pageCount,
            currentIndex: model.currentIndex,
            currentLabel: model.currentLabel,
            hasNext: model.nextIndex != nil,
            slideAspect: Double(model.slideAspect),
            tool: model.tool,
            penColorIndex: model.penColorIndex,
            blank: model.blank,
            magnify: model.magnify,
            preset: model.preset,
            splitMode: model.splitMode,
            isSplit: model.isSplit,
            presenting: isPresenting(),
            externalDisplays: externalDisplays(),
            notesText: model.isSplit ? nil : model.currentNotesText,
            timerRunning: model.timerRunning,
            accumulated: model.accumulated,
            startedAtEpoch: model.startedAt?.timeIntervalSince1970,
            talkLength: model.talkLength)
    }

    private func strokesSignature() -> String {
        let arr = model.strokes[model.currentIndex] ?? []
        return "\(model.currentIndex)|\(arr.count)|\(arr.last?.points.count ?? 0)"
    }

    private func sendFullSync(to devices: [String]) {
        link.send(.state(buildState()), to: devices)
        sendThumbnails(to: devices)
        sendStrokes(to: devices)
    }

    private func sendThumbnails(to devices: [String]) {
        sendThumbnail(index: model.currentIndex, kind: .slide, to: devices)
        if let n = model.nextIndex { sendThumbnail(index: n, kind: .slide, to: devices) }
        if model.isSplit { sendThumbnail(index: model.currentIndex, kind: .notes, to: devices) }
    }

    private func sendStrokes(to devices: [String]) {
        link.send(.strokes(index: model.currentIndex, strokes: model.strokes[model.currentIndex] ?? []),
                  to: devices)
    }

    private func sendThumbnail(index: Int, kind: SlideKind, to devices: [String]) {
        guard let doc = model.document, index >= 0, index < model.pageCount,
              let page = doc.page(at: index) else { return }
        let region: CGRect
        switch kind {
        case .slide: region = model.slideRegion(for: page)
        case .notes: guard let n = model.notesRegion(for: page) else { return }; region = n
        }
        guard region.width > 0, region.height > 0 else { return }
        let key = "remote-\(model.docToken)-\(index)-\(kind.rawValue)-\(model.isSplit)"
        let img = SlideRenderer.shared.image(page: page, region: region, key: key, pixelWidth: 1280)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
        link.send(.thumbnail(index: index, kind: kind, jpeg: jpeg,
                             aspect: Double(region.width / region.height), token: model.docToken),
                  to: devices)
    }
}
