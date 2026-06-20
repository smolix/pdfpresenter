// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI
import Observation

/// Observable mirror of the RemoteServer's status, bound to the pairing panel.
@Observable final class RemoteStatus {
    var code: String = "------"
    var connected: Int = 0
    var pairedDevices: [String] = []
    var advertising: Bool = false
}

/// The "Remote Control" panel: shows the pairing code to type on the companion
/// app, plus connection status and trust management.
struct RemotePanel: View {
    @Bindable var status: RemoteStatus
    var onRegenerate: () -> Void = {}
    var onForget: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("PDF Presenter on iPhone / iPad").font(.headline)
                    Text(status.advertising ? "Discoverable on Wi-Fi & Bluetooth" : "Off")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PAIRING CODE").font(.system(size: 10, weight: .bold)).tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(spacedCode)
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .tracking(6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                Text("On your iPhone or iPad, open the **PDF Presenter** app, tap this Mac, "
                     + "and enter this code. Paired devices reconnect automatically.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 8) {
                Circle().fill(status.connected > 0 ? Color.green : Color.secondary).frame(width: 9, height: 9)
                Text(statusLine).font(.callout)
                Spacer()
            }
            if !status.pairedDevices.isEmpty {
                Text("Paired: " + status.pairedDevices.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Regenerate Code", action: onRegenerate)
                Spacer()
                Button("Forget Paired Devices", role: .destructive, action: onForget)
                    .disabled(status.pairedDevices.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var spacedCode: String {
        let c = status.code.count == 6 ? status.code : "------"
        return String(c.prefix(3)) + " " + String(c.suffix(3))
    }
    private var statusLine: String {
        let paired = status.pairedDevices.count
        if status.connected == 0 { return "No devices connected" }
        return "\(status.connected) connected · \(paired) paired"
    }
}
