import SwiftUI
import AppKit

@main
struct DiskLensApp: App {
    init() {
        // 作为 Swift Package 直接运行时,也要让它显示成普通窗口应用
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("DiskLens") {
            ContentView()
        }
    }
}
