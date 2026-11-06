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
            RootView()
        }
    }
}

/// ViewModel 放在这一层;切换语言 / 配色时,只重建下面的界面(version 变化 → .id 变化),
/// 扫描结果和收集器里的内容都不受影响。
struct RootView: View {
    @StateObject private var vm = ViewModel()
    @State private var version = 0

    var body: some View {
        ContentView(vm: vm, onPrefsChange: { version += 1 })
            .id(version)
            .tint(Prefs.theme.accent)
            .preferredColorScheme(Prefs.theme.scheme)
    }
}
