// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import AppKit

/// Keeps the display awake — no dimming, no screensaver — while a presentation
/// is up on the audience screen, so a slide never blacks out mid-talk. It yields
/// to the OS the moment Low Power Mode turns on (a low battery): then the Mac is
/// free to dim and sleep exactly as the user's energy settings dictate, rather
/// than draining a near-flat battery to hold a slide nobody is watching.
///
/// Built on `ProcessInfo.beginActivity(.idleDisplaySleepDisabled)` — the same
/// power assertion video players and Keynote use. The assertion is released the
/// instant presenting stops or Low Power Mode kicks in, and re-taken if the user
/// plugs back in (Low Power Mode clears) while still presenting.
final class WakeGuard {
    private var activity: NSObjectProtocol?
    private var presenting = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }

    /// Call on every present/hide transition. Idempotent.
    func setPresenting(_ on: Bool) {
        guard presenting != on else { return }
        presenting = on
        update()
    }

    @objc private func powerStateChanged() {
        DispatchQueue.main.async { [weak self] in self?.update() }
    }

    private func update() {
        let shouldHold = presenting && !ProcessInfo.processInfo.isLowPowerModeEnabled
        if shouldHold {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "Presenting slides to the audience display")
        } else if let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }
}
