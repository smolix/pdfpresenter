// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation

/// Watches the open PDF on disk and fires `onReload` once it has *stopped*
/// changing — so a deck that's mid-rebuild (pdflatex still writing the file) is
/// never loaded half-finished. It polls the file's modification time and size;
/// when those differ from the loaded version it starts a stability clock, and
/// only reloads after the file has been unchanged for `stableFor` seconds. A
/// rebuild that keeps writing (or a two-pass LaTeX run) just keeps resetting the
/// clock until the dust settles. Polling by path also survives atomic replaces
/// (write-temp-then-rename), which a file-descriptor watch would miss.
final class DocumentWatcher {

    private struct Signature: Equatable { let mtime: Date; let size: Int64 }

    var isEnabled = true { didSet { if !isEnabled { resetPending() } } }

    private let pollInterval: TimeInterval = 1.0
    private let stableFor: TimeInterval = 5.0
    private let onReload: () -> Void

    private var url: URL?
    private var timer: Timer?
    private var loadedSig: Signature?     // the version currently displayed
    private var pendingSig: Signature?    // a changed version awaiting stability
    private var pendingSince: Date?

    init(onReload: @escaping () -> Void) { self.onReload = onReload }

    /// Begin watching `url`, treating its current on-disk state as the loaded one.
    func watch(_ url: URL) {
        self.url = url
        loadedSig = Self.signature(of: url)
        resetPending()
        start()
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Call after the app itself (re)loads the file, so we don't immediately
    /// detect that load as an external change.
    func markLoaded() {
        if let url { loadedSig = Self.signature(of: url) }
        resetPending()
    }

    private func resetPending() { pendingSig = nil; pendingSince = nil }

    private func start() {
        stop()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)   // keeps firing during menu tracking, etc.
        timer = t
    }

    private func tick() {
        guard isEnabled, let url, let cur = Self.signature(of: url) else { return }
        if cur == loadedSig {                 // matches what's shown — nothing to do
            resetPending()
        } else if cur == pendingSig {         // unchanged since we first noticed it
            if let since = pendingSince, Date().timeIntervalSince(since) >= stableFor {
                resetPending()
                onReload()                    // caller reloads, then calls markLoaded();
                                              // if the reload fails we'll re-detect and retry
            }
        } else {                              // changed (again) — restart the stability clock
            pendingSig = cur
            pendingSince = Date()
        }
    }

    private static func signature(of url: URL) -> Signature? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let m = a[.modificationDate] as? Date,
              let s = (a[.size] as? NSNumber)?.int64Value else { return nil }
        return Signature(mtime: m, size: s)
    }
}
