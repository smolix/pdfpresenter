// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import Foundation

// Small runtime-policy helpers, factored out so the OS-touching wrappers (the
// macOS WakeGuard, the iOS idle-timer, the file watcher) stay thin and the
// decisions they make can be unit-tested deterministically.

/// Whether the display should be held awake. True only while presenting *and*
/// the OS is not in Low Power Mode — so a low battery is still free to dim and
/// sleep per the user's settings. Shared by the macOS power assertion and the
/// iOS `isIdleTimerDisabled` policy so both platforms decide identically.
public func shouldKeepAwake(presenting: Bool, lowPower: Bool) -> Bool {
    presenting && !lowPower
}

/// A pure state machine that decides when a file being rewritten on disk has
/// "settled" enough to (re)load — so a deck caught mid-rebuild is never loaded
/// half-finished. Fed an observed signature (e.g. mtime+size) and the current
/// time on each poll; it reports ready exactly once, after the signature has held
/// steady — and differs from the loaded one — for `stableFor` seconds. A rebuild
/// that keeps writing just keeps resetting the clock.
///
/// The clock is passed in (`now:`) rather than read from `Date()`, so tests can
/// fast-forward through the stabilization window instead of sleeping in realtime.
public struct FileStabilityGate<Signature: Equatable> {
    public let stableFor: TimeInterval
    private var loaded: Signature?       // the version currently displayed
    private var pending: Signature?      // a changed version awaiting stability
    private var pendingSince: Date?

    public init(stableFor: TimeInterval, loaded: Signature? = nil) {
        self.stableFor = stableFor
        self.loaded = loaded
    }

    /// Re-baseline to the signature that was just loaded; clears any pending
    /// change (so the app's own load isn't re-detected as an external edit).
    public mutating func markLoaded(_ signature: Signature?) {
        loaded = signature
        resetPending()
    }

    /// Forget a change in progress without touching the loaded baseline (used
    /// when watching is paused).
    public mutating func resetPending() {
        pending = nil
        pendingSince = nil
    }

    /// Feed the current on-disk signature and the current time. Returns true
    /// exactly once — when `current` differs from the loaded baseline and has held
    /// steady for `stableFor`. A nil signature (an unreadable file mid-write) is
    /// ignored, leaving any in-progress stability clock untouched.
    public mutating func observe(_ current: Signature?, now: Date) -> Bool {
        guard let current else { return false }
        if current == loaded {                 // matches what's shown — nothing to do
            resetPending()
            return false
        }
        if current == pending {                // unchanged since we first noticed it
            if let since = pendingSince, now.timeIntervalSince(since) >= stableFor {
                resetPending()
                return true
            }
            return false
        }
        pending = current                      // changed (again) — restart the clock
        pendingSince = now
        return false
    }
}
