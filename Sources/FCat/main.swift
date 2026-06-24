import AppKit

final class AppDelegateHolder {
    static let delegate = AppDelegate()
}

let app = NSApplication.shared
app.delegate = AppDelegateHolder.delegate
app.setActivationPolicy(.accessory)
app.run()
