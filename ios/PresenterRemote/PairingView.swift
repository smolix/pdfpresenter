// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import SwiftUI

/// Discovery + pairing. Shows progress while searching/connecting and a code
/// field once a Mac is found, matching the code shown in the Mac's "Remote
/// Control" panel.
struct PairingView: View {
    @Bindable var conn: ConnectionModel
    @State private var code = ""
    @State private var lastSubmitted = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 54)).foregroundStyle(.blue)
            Text("PDF Presenter Remote").font(.title2.weight(.semibold))

            switch conn.phase {
            case .searching:
                statusBlock(icon: "wifi", text: "Looking for your Mac…", spin: true)
                Text("Make sure PDF Presenter is open on your Mac and you're on the same Wi-Fi or Bluetooth.")
                    .footnote()

            case .needsCode, .rejected:
                VStack(spacing: 14) {
                    if let mac = conn.macName {
                        Text("Connected to **\(mac)**").font(.callout)
                    }
                    if case .rejected(let why) = conn.phase {
                        Text(why).font(.callout).foregroundStyle(.red)
                    }
                    Text("Enter the 6-digit code from the Mac's Remote Control panel "
                         + "(Remote ▸ Pairing & Status).").footnote()
                    codeField
                    Button {
                        conn.submitCode(code.filter(\.isNumber))
                    } label: {
                        Text("Pair").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(code.filter(\.isNumber).count != 6)
                }
                .padding(.horizontal, 32)

            case .pairing:
                statusBlock(icon: "lock.shield", text: "Pairing…", spin: true)

            case .ready:
                EmptyView()
            }
            Spacer()
        }
        .frame(maxWidth: 460)
        .padding()
    }

    private var codeField: some View {
        TextField("000000", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
            .tracking(8)
            .focused($codeFocused)
            .padding(.vertical, 12)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: code) { _, new in
                code = String(new.filter(\.isNumber).prefix(6))
                // Auto-submit once the 6th digit lands (like an SMS code field).
                if code.count == 6, code != lastSubmitted {
                    lastSubmitted = code
                    conn.submitCode(code)
                }
            }
            .onAppear { codeFocused = true }
    }

    private func statusBlock(icon: String, text: String, spin: Bool) -> some View {
        HStack(spacing: 10) {
            if spin { ProgressView() }
            Text(text).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func footnote() -> some View {
        self.font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).padding(.horizontal, 24)
    }
}
