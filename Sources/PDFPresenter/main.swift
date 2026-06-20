// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Alex Smola

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
