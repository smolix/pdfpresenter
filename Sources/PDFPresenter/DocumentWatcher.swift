// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation
import PresenterKit

/// Watches the open PDF on disk and fires `onReload` once it has *stopped*
/// changing — so a deck that's mid-rebuild (pdflatex still writing the file) is
/// never loaded half-finished. It polls the file's modification time and size and
/// hands each reading to a `FileStabilityGate`, which holds back the reload until
/// the file has been unchanged for `stableFor` seconds. Polling by path also
/// survives atomic replaces (write-temp-then-rename), which a file-descriptor
/// watch would miss.
///
/// All the "has it settled yet?" logic lives in `FileStabilityGate` (in
/// PresenterKit) so it can be unit-tested with a fake clock; this class is just
/// the timer + filesystem plumbing around it.
final class DocumentWatcher {

    private struct Signature: Equatable { let mtime: Date; let size: Int64 }

    var isEnabled = true { didSet { if !isEnabled { gate.resetPending() } } }

    private let pollInterval: TimeInterval = 1.0
    private let onReload: () -> Void

    private var url: URL?
    private var timer: Timer?
    private var gate = FileStabilityGate<Signature>(stableFor: 5.0)

    init(onReload: @escaping () -> Void) { self.onReload = onReload }

    /// Begin watching `url`, treating its current on-disk state as the loaded one.
    func watch(_ url: URL) {
        self.url = url
        gate.markLoaded(Self.signature(of: url))
        start()
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Call after the app itself (re)loads the file, so we don't immediately
    /// detect that load as an external change.
    func markLoaded() {
        if let url { gate.markLoaded(Self.signature(of: url)) }
    }

    private func start() {
        stop()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)   // keeps firing during menu tracking, etc.
        timer = t
    }

    private func tick() {
        guard isEnabled, let url else { return }
        if gate.observe(Self.signature(of: url), now: Date()) {
            onReload()   // caller reloads, then calls markLoaded();
                         // if the reload fails we'll re-detect and retry
        }
    }

    private static func signature(of url: URL) -> Signature? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let m = a[.modificationDate] as? Date,
              let s = (a[.size] as? NSNumber)?.int64Value else { return nil }
        return Signature(mtime: m, size: s)
    }
}
