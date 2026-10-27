import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = DisplayController()
app.delegate = controller
app.run()
