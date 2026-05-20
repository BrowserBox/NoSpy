// NoSpyBar — menu bar companion to the nospy CLI. Same NoSpyCore powers both;
// this target is just AppKit glue: a status item, a menu, and a 2s poll.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon, no app menu — pure menu bar

let controller = StatusController()
app.delegate = controller
app.run()
