// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import UIKit

/// Shared hand-off between the presenter UI and the external-display scene.
/// The presenter sets `deck` while presenting; the external `UIWindowScene`
/// (created by iOS when a display connects) observes it and shows the audience.
@MainActor @Observable
final class PresentationSession {
    static let shared = PresentationSession()
    var deck: LocalDeck?
    var externalConnected = false
}

/// Root of the external display: the audience slide once a deck is presenting,
/// otherwise a ready hint. Observes the shared session, so it tracks navigation
/// and ink live.
struct ExternalAudienceRoot: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let deck = PresentationSession.shared.deck {
                LocalAudienceView(deck: deck)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 48))
                    Text("PDF Presenter").font(.title2.weight(.semibold))
                    Text("Open a PDF on your iPad to present here.").foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Scene delegate for a connected external display (declared in Info.plist's
/// scene manifest). iOS instantiates this when a display attaches; it hosts the
/// audience view in a window on that screen.
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let bounds = windowScene.screen.bounds   // the external display's full size
        let w = UIWindow(frame: bounds)
        w.windowScene = windowScene
        let host = UIHostingController(rootView: ExternalAudienceRoot())
        host.view.frame = bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .black
        w.rootViewController = host
        w.isHidden = false
        window = w
        MainActor.assumeIsolated { PresentationSession.shared.externalConnected = true }
    }

    /// Keep the window filling the screen if its geometry changes.
    func windowScene(_ windowScene: UIWindowScene,
                     didUpdate previousCoordinateSpace: UICoordinateSpace,
                     interfaceOrientation: UIInterfaceOrientation,
                     traitCollection: UITraitCollection) {
        let bounds = windowScene.screen.bounds
        window?.frame = bounds
        window?.rootViewController?.view.frame = bounds
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated { PresentationSession.shared.externalConnected = false }
    }
}
