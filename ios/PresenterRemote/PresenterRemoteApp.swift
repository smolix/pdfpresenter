// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if conn.isReady {
                RemoteControlView(conn: conn)
            } else {
                PairingView(conn: conn)
            }
        }
    }
}
