// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import SwiftUI
import UIKit
import PresenterKit

/// Drives the link to the Mac: discovery, pairing, the mirrored presenter state,
/// slide images, and outgoing control / pointer / stroke messages. All state is
/// observed by the SwiftUI views; PeerLink delivers callbacks on the main queue.
@MainActor @Observable
final class ConnectionModel: NSObject, PeerLinkDelegate {

    enum Phase: Equatable {
        case searching          // looking for a Mac
        case needsCode          // connected, waiting for the user to enter the code
        case pairing            // code sent, awaiting confirmation
        case ready              // paired & mirroring
        case rejected(String)   // wrong code / refused
    }

    private(set) var phase: Phase = .searching
    private(set) var macName: String?
    /// The host (Mac) peer — identified as whoever sends us state/pairing. With
    /// an iPhone and iPad both connected they mesh, so we must target the Mac
    /// specifically rather than broadcasting to every peer.
    private(set) var hostDevice: String?

    private(set) var state: PresenterState?
    private(set) var slideImages: [Int: UIImage] = [:]
    private(set) var notesImage: UIImage?
    private(set) var notesToken = -1
    private(set) var currentStrokes: [Stroke] = []
    private(set) var overviewImages: [Int: UIImage] = [:]   // small, for the grid

    /// The image to actually show on the stage: the current slide once its image
    /// has arrived, otherwise the *previous* slide (so advancing never flashes to
    /// black while the new slide loads).
    private(set) var displayImage: UIImage?
    private var displayIndex = -1

    /// In-progress local stroke, shown immediately while drawing on iPad.
    var liveStroke: Stroke?
    /// Where the laser/spotlight/zoom is, locally, so the iOS slide shows the
    /// same effect the audience sees (only while a finger/Pencil is down).
    var localPointer: CGPoint?

    private let link: PeerLink
    private let deviceName: String
    private var pendingCode: String?
    private static let savedCodeKey = "remotePairedCode"

    override init() {
        self.deviceName = UIDevice.current.name
        self.link = PeerLink(role: .client, displayName: deviceName)
        super.init()
        link.delegate = self
    }

    func start() { link.start() }
    func stop() { link.stop() }

    #if DEBUG
    /// Offline UI harness (launch with `-demo`): shows the connected UI with mock
    /// state so the layout can be checked without a live Mac (Multipeer is flaky
    /// in the Simulator). Tool is `.pen` so the colour swatches show too.
    func enterDemoMode() {
        let drawing = CommandLine.arguments.contains("-pen")
        let running = CommandLine.arguments.contains("-running")
        macName = "Demo Mac"; hostDevice = "Demo Mac"
        phase = .ready
        state = PresenterState(
            docToken: 1, documentName: "demo.pdf", pageCount: 10, currentIndex: 0, currentLabel: "1",
            hasNext: true, slideAspect: 16.0 / 9.0, tool: drawing ? .pen : .off, penColorIndex: 0,
            blank: .none, magnify: false, preset: .notesRight, splitMode: .auto, isSplit: false,
            presenting: true, externalDisplays: 1, notesText: "Demo notes for this slide.",
            timerRunning: running, accumulated: 0,
            startedAtEpoch: running ? Date().timeIntervalSince1970 - 65 : nil, talkLength: 0)
    }
    #endif

    #if DEBUG
    /// Launch-arg requests for the demo harness to open a dialog on appear.
    var demoShowJump: Bool { CommandLine.arguments.contains("-jump") }
    var demoShowConnection: Bool { CommandLine.arguments.contains("-conn") }
    #endif

    var isReady: Bool { phase == .ready }

    // MARK: Pairing

    func submitCode(_ code: String) {
        pendingCode = code
        phase = .pairing
        link.send(.pair(code: code, device: deviceName))
    }

    private func autoPairIfPossible() {
        if let saved = UserDefaults.standard.string(forKey: Self.savedCodeKey) {
            submitCode(saved)
        } else {
            phase = .needsCode
        }
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.savedCodeKey)
        pendingCode = nil
        phase = link.connectedDevices.isEmpty ? .searching : .needsCode
    }

    // MARK: Outgoing

    private var host: [String]? { hostDevice.map { [$0] } }

    func send(_ command: RemoteCommand) { guard isReady else { return }; link.send(.command(command), to: host) }
    func sendPointer(_ p: CGPoint?) { guard isReady else { return }; link.send(.pointer(p), to: host) }
    func sendErase(_ p: CGPoint) { guard isReady else { return }; link.send(.erase(p), to: host) }
    func requestOverview() { guard isReady else { return }; link.send(.requestAllThumbnails, to: host) }

    /// Adopt the current slide's image once it's available; otherwise keep the
    /// previous one on screen (no black flash mid-advance).
    private func refreshDisplay() {
        guard let i = state?.currentIndex else { return }
        if i != displayIndex, let img = slideImages[i] {
            displayImage = img
            displayIndex = i
        } else if displayImage == nil, let img = slideImages[i] {
            displayImage = img; displayIndex = i
        }
    }

    func beginStroke(_ s: Stroke) {
        guard isReady else { return }
        liveStroke = s
        link.send(.strokeBegin(s), to: host)
    }
    func extendStroke(_ p: CGPoint) {
        guard isReady, liveStroke != nil else { return }
        liveStroke?.points.append(p)
        link.send(.strokeExtend(p), to: host)
    }
    func endStroke() {
        guard isReady else { return }
        liveStroke = nil
        link.send(.strokeEnd, to: host)
    }

    // MARK: PeerLinkDelegate
    // PeerLink always calls these on the main queue, so we hop onto the main
    // actor to touch observed state (the protocol itself is non-isolated).

    nonisolated func peerLinkConnectionChanged(_ link: PeerLink) {
        MainActor.assumeIsolated { self.connectionChanged(link) }
    }
    nonisolated func peerLink(_ link: PeerLink, didReceive message: PresenterMessage, from device: String) {
        MainActor.assumeIsolated { self.handle(message, from: device) }
    }

    private func connectionChanged(_ link: PeerLink) {
        if link.connectedDevices.isEmpty {
            macName = nil; hostDevice = nil
            state = nil; slideImages = [:]; notesImage = nil; currentStrokes = []
            phase = .searching
        } else {
            // Provisional until the host identifies itself by sending us state.
            if hostDevice == nil { macName = link.connectedDevices.first }
            if phase == .searching { autoPairIfPossible() }
        }
    }

    private func handle(_ message: PresenterMessage, from device: String) {
        // Whoever sends host-only messages is the Mac; lock onto it.
        switch message {
        case .paired, .state, .thumbnail, .overviewThumbnail, .strokes:
            hostDevice = device; macName = device
        default:
            break
        }
        switch message {
        case .paired(let ok, let reason):
            if ok {
                if let c = pendingCode { UserDefaults.standard.set(c, forKey: Self.savedCodeKey) }
                phase = .ready
                link.send(.requestThumbnails, to: host)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.savedCodeKey)
                phase = .rejected(reason ?? "Pairing refused")
            }

        case .state(let s):
            if s.docToken != state?.docToken {
                slideImages = [:]; notesImage = nil; notesToken = -1; overviewImages = [:]
                displayImage = nil; displayIndex = -1
            }
            state = s
            refreshDisplay()

        case .thumbnail(let index, let kind, let jpeg, _, let token):
            guard let img = UIImage(data: jpeg) else { return }
            switch kind {
            case .slide: slideImages[index] = img; refreshDisplay()
            case .notes: notesImage = img; notesToken = token
            }

        case .overviewThumbnail(let index, let jpeg, _):
            if let img = UIImage(data: jpeg) { overviewImages[index] = img }

        case .strokes(let index, let strokes):
            if index == state?.currentIndex { currentStrokes = strokes }

        default:
            break   // other cases are Mac-bound
        }
    }
}

// Map the shared palette to SwiftUI colors so ink matches the Mac exactly.
func remoteColor(_ i: Int) -> Color {
    let c = annotationPalette[annotationPaletteIndex(i)]
    return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
}
