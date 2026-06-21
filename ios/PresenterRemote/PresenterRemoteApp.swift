// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import UniformTypeIdentifiers

@main
struct PresenterRemoteApp: App {
    @State private var conn = ConnectionModel()

    var body: some Scene {
        WindowGroup {
            ContentView(conn: conn)
                .preferredColorScheme(.dark)
                .tint(.blue)
                .onAppear {
                    #if DEBUG
                    if CommandLine.arguments.contains("-demo") { conn.enterDemoMode(); return }
                    #endif
                    conn.start()
                }
        }
    }
}

struct ContentView: View {
    @Bindable var conn: ConnectionModel

    // Standalone (no-Mac) presentation driven by this device.
    @State private var deck = LocalDeck()
    @State private var showPicker = false
    @State private var presentLocal = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if conn.isReady {
                RemoteControlView(conn: conn)
            } else {
                PairingView(conn: conn) { showPicker = true }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            deck.load(url: url)
            presentLocal = true
        }
        .fullScreenCover(isPresented: $presentLocal) {
            LocalPresenterView(deck: deck) { presentLocal = false }
                .preferredColorScheme(.dark)
        }
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("-localdemo") {
                deck.loadDemo()
                presentLocal = true
            }
            #endif
        }
    }
}
