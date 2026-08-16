import AppKit

// Courier uses an explicit entry point rather than @main so that application
// setup order stays visible and testable.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
