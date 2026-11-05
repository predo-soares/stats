import SwiftUI

@main
struct statsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // Use the adaptor-owned AppDelegate. `NSApp.delegate` is not reliably this
            // instance for SwiftUI apps, so casting it left Settings on an endless ProgressView.
            SettingsView(store: appDelegate.usageStore)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
