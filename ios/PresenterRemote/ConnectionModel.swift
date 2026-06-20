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

    private(set) var state: PresenterState?
    private(set) var slideImages: [Int: UIImage] = [:]
    private(set) var notesImage: UIImage?
    private(set) var notesToken = -1
    private(set) var currentStrokes: [Stroke] = []

    /// In-progress local stroke, shown immediately while drawing on iPad.
    var liveStroke: Stroke?

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

    func send(_ command: RemoteCommand) { guard isReady else { return }; link.send(.command(command)) }
    func sendPointer(_ p: CGPoint?) { guard isReady else { return }; link.send(.pointer(p)) }
    func sendErase(_ p: CGPoint) { guard isReady else { return }; link.send(.erase(p)) }

    func beginStroke(_ s: Stroke) {
        guard isReady else { return }
        liveStroke = s
        link.send(.strokeBegin(s))
    }
    func extendStroke(_ p: CGPoint) {
        guard isReady, liveStroke != nil else { return }
        liveStroke?.points.append(p)
        link.send(.strokeExtend(p))
    }
    func endStroke() {
        guard isReady else { return }
        liveStroke = nil
        link.send(.strokeEnd)
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
            macName = nil
            state = nil; slideImages = [:]; notesImage = nil; currentStrokes = []
            phase = .searching
        } else {
            macName = link.connectedDevices.first
            if phase == .searching { autoPairIfPossible() }
        }
    }

    private func handle(_ message: PresenterMessage, from device: String) {
        switch message {
        case .paired(let ok, let reason):
            if ok {
                if let c = pendingCode { UserDefaults.standard.set(c, forKey: Self.savedCodeKey) }
                phase = .ready
                link.send(.requestThumbnails)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.savedCodeKey)
                phase = .rejected(reason ?? "Pairing refused")
            }

        case .state(let s):
            if s.docToken != state?.docToken { slideImages = [:]; notesImage = nil; notesToken = -1 }
            state = s

        case .thumbnail(let index, let kind, let jpeg, _, let token):
            guard let img = UIImage(data: jpeg) else { return }
            switch kind {
            case .slide: slideImages[index] = img
            case .notes: notesImage = img; notesToken = token
            }

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
