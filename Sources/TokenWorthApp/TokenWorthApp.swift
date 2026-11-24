import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TokenWorthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView(state: appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                if let labelText = appState.menuBarLabelText {
                    Text(labelText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
