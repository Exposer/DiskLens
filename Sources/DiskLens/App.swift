import SwiftUI
import AppKit

@main
struct DiskLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// 磁盘监控归整个 App 所有:窗口关掉(隐藏)之后依然继续
    @StateObject private var monitor = DiskMonitor()
    @AppStorage("showMenuBar") private var showMenuBar = true

    init() {
        // 作为 Swift Package 直接运行时,也要让它显示成普通窗口应用
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        // 单窗口。关闭窗口只是隐藏(见 AppDelegate),扫描结果会保留
        Window("DiskLens", id: "main") {
            RootView(monitor: monitor)
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// ViewModel 放在这一层;切换语言 / 配色时,只重建下面的界面(version 变化 → .id 变化),
/// 扫描结果和收集器里的内容都不受影响。
struct RootView: View {
    @StateObject private var vm = ViewModel()
    @ObservedObject var monitor: DiskMonitor
    @State private var version = 0

    var body: some View {
        ContentView(vm: vm, monitor: monitor, onPrefsChange: { version += 1 })
            .id(version)
            .onAppear { monitor.start() }
            .background(WindowAccessor { AppDelegate.shared?.adopt($0) })
            .tint(Prefs.theme.accent)
            .preferredColorScheme(Prefs.theme.scheme)
    }
}
