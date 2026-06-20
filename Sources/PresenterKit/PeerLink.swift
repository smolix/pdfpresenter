// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import MultipeerConnectivity

public enum PeerRole: Sendable { case host, client }

/// Delivered on the main queue.
public protocol PeerLinkDelegate: AnyObject {
    /// A decoded message arrived from `device` (the peer's display name).
    func peerLink(_ link: PeerLink, didReceive message: PresenterMessage, from device: String)
    /// The set of connected devices changed.
    func peerLinkConnectionChanged(_ link: PeerLink)
}

/// A thin Multipeer Connectivity transport shared by the macOS host and the iOS
/// companion. It carries `PresenterMessage`s over an encrypted `MCSession`,
/// auto-selecting Wi-Fi / peer-to-peer Wi-Fi / Bluetooth. Pairing/trust is left
/// to the app layer; this only moves bytes and reports who's connected.
public final class PeerLink: NSObject {
    public weak var delegate: PeerLinkDelegate?
    public let role: PeerRole

    private let serviceType: String
    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// Display names of currently-connected peers (main-queue updated).
    public private(set) var connectedDevices: [String] = []

    public init(role: PeerRole, displayName: String, serviceType: String = presenterServiceType) {
        let trimmed = displayName.isEmpty ? "Device" : String(displayName.prefix(63))
        self.role = role
        self.serviceType = serviceType
        self.myPeerID = MCPeerID(displayName: trimmed)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    public func start() {
        switch role {
        case .host:
            let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
            adv.delegate = self
            adv.startAdvertisingPeer()
            advertiser = adv
        case .client:
            let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            br.delegate = self
            br.startBrowsingForPeers()
            browser = br
        }
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session.disconnect()
    }

    /// Send to specific devices by display name, or to all connected peers when
    /// `devices` is nil.
    public func send(_ message: PresenterMessage, to devices: [String]? = nil) {
        let peers: [MCPeerID]
        if let devices {
            let want = Set(devices)
            peers = session.connectedPeers.filter { want.contains($0.displayName) }
        } else {
            peers = session.connectedPeers
        }
        guard !peers.isEmpty, let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func refreshConnected() {
        let names = session.connectedPeers.map(\.displayName)
        DispatchQueue.main.async {
            self.connectedDevices = names
            self.delegate?.peerLinkConnectionChanged(self)
        }
    }
}

extension PeerLink: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        refreshConnected()
    }
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(PresenterMessage.self, from: data) else { return }
        let device = peerID.displayName
        DispatchQueue.main.async { self.delegate?.peerLink(self, didReceive: msg, from: device) }
    }
    // Unused channels (required by the protocol).
    public func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    public func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Progress) {}
    public func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerLink: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                           didReceiveInvitationFromPeer peerID: MCPeerID,
                           withContext context: Data?,
                           invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept into the encrypted session; control stays gated behind the
        // app-level pairing code until the peer proves it.
        invitationHandler(true, session)
    }
}

extension PeerLink: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                        withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        refreshConnected()
    }
}
