import AppKit

// Override AppleLanguages before any localized resource is touched.
Preferences.applyLanguageAtLaunch()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
