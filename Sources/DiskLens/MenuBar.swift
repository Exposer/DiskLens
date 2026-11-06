import SwiftUI
import AppKit
import ServiceManagement

// 菜单栏图标:显示可用空间、快速查看容量、打开主窗口。
// 关掉主窗口不会退出 DiskLens(窗口只是被隐藏),所以磁盘监控和菜单栏图标会继续工作;
// 要退出,请用菜单栏图标里的「退出 DiskLens」或 ⌘Q。

/// 菜单栏上用的短格式大小,例如 38 GB / 1.2 TB
func compactSize(_ bytes: Int64) -> String {
    let b = Double(bytes)
    if b >= 1e12 { return String(format: "%.1f TB", b / 1e12) }
    return String(format: "%.0f GB", b / 1e9)
}

// MARK: - AppDelegate:关窗口不退出,点 Dock 图标恢复窗口

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    private(set) var mainWindow: NSWindow?

    /// 这次是不是开机(登录)时自动启动的:true 时不弹窗口,只在菜单栏里待着
    private var hideOnLaunch = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    /// 是否由“登录时自动打开”启动的(必须在 applicationDidFinishLaunching 里读取)
    private static var wasLaunchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let d = UserDefaults.standard
        let menuBarOn = d.object(forKey: "showMenuBar") as? Bool ?? true
        let wantsWindow = d.bool(forKey: "loginShowWindow")
        // 开机自动启动 → 不弹窗口、不在 Dock 里跳。但如果菜单栏图标被关掉了,就没有入口可以打开窗口,此时照常显示。
        if Self.wasLaunchedAtLogin && menuBarOn && !wantsWindow {
            hideOnLaunch = true
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    /// 记住主窗口,并让“关闭”变成“隐藏”(窗口和里面的扫描结果都保留着)
    func adopt(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        if hideOnLaunch {
            hideOnLaunch = false
            hideQuietly(window)
            // SwiftUI 可能在这之后才把窗口显示出来,所以窗口现在先设成完全透明、不响应鼠标,
            // 即使它被显示了,用户也看不到、点不到;showMainWindow() 会恢复。
            for delay in [0.2, 0.6, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.isQuiet else { return }
                    window.orderOut(nil)
                }
            }
        }
    }

    private var isQuiet = false

    private func hideQuietly(_ window: NSWindow) {
        isQuiet = true
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func showMainWindow() {
        // 开机启动时用的是“无 Dock 图标”模式,打开窗口时恢复成普通应用
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let w = mainWindow else { return }
        isQuiet = false
        w.alphaValue = 1
        w.ignoresMouseEvents = false
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil)
    }
}

/// 取出 SwiftUI 窗口背后的 NSWindow
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window { onWindow(w) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { onWindow(w) }
        }
    }
}

// MARK: - 开机自动启动

enum LaunchAtLogin {
    /// 只有打包成 .app 才能注册为登录项
    static var available: Bool { Notifier.available }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) {
        guard available else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("DiskLens: launch at login failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - 菜单栏图标本身

struct MenuBarLabel: View {
    @ObservedObject var monitor: DiskMonitor
    @AppStorage("menuBarShowText") private var showText = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: monitor.lowSpace != nil ? "exclamationmark.triangle.fill" : "internaldrive")
            if showText, let u = monitor.usage {
                Text(compactSize(u.available))
            }
        }
        // 窗口被隐藏(比如开机自动启动)时,菜单栏图标是最先出现的界面,监控从这里也要能启动
        .onAppear { monitor.start() }
    }
}

// MARK: - 点开菜单栏图标后的面板

struct MenuBarContent: View {
    @ObservedObject var monitor: DiskMonitor
    @AppStorage("menuBarShowText") private var showText = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("loginShowWindow") private var loginShowWindow = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let u = monitor.usage {
                capacity(u)
            } else {
                Text(tr("无法读取磁盘容量", "Unable to read disk capacity"))
                    .foregroundStyle(.secondary)
            }

            if monitor.lowSpace != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(tr("磁盘空间不足", "Disk space is running low"))
                        .font(.callout.weight(.medium))
                }
            }

            Divider()

            Button {
                AppDelegate.shared?.showMainWindow()
            } label: {
                Label(tr("打开 DiskLens 窗口", "Open DiskLens Window"), systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            HStack {
                LowSpaceMenu(monitor: monitor)
                Spacer()
            }

            Toggle(tr("菜单栏里显示可用空间", "Show available space in the menu bar"), isOn: $showText)
                .toggleStyle(.checkbox)
                .font(.callout)

            Toggle(tr("开机时自动启动", "Launch at login"), isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    LaunchAtLogin.set(on)
                    launchAtLogin = LaunchAtLogin.isEnabled
                })
            )
            .toggleStyle(.checkbox)
            .font(.callout)
            .disabled(!LaunchAtLogin.available)
            .help(LaunchAtLogin.available
                  ? tr("登录 Mac 后自动在菜单栏启动 DiskLens", "Start DiskLens in the menu bar when you log in")
                  : tr("只有打包后的 DiskLens.app 才能设置开机启动", "Only the packaged DiskLens.app can launch at login"))

            Toggle(tr("开机启动时显示窗口", "Show the window when launched at login"), isOn: $loginShowWindow)
                .toggleStyle(.checkbox)
                .font(.callout)
                .disabled(!LaunchAtLogin.available)
                .help(tr("默认只在菜单栏里安静地启动,不弹出窗口", "By default DiskLens starts quietly in the menu bar without opening a window"))

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(tr("退出 DiskLens", "Quit DiskLens"), systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            monitor.check()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func capacity(_ u: VolumeUsage) -> some View {
        let total = Double(max(u.total, 1))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatSize(u.available))
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text(tr("可用 / 共 \(formatSize(u.total))", "available of \(formatSize(u.total))"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25))
                    HStack(spacing: 0) {
                        Rectangle().fill(tc(0.58, 0.6, 0.85))
                            .frame(width: g.size.width * CGFloat(Double(u.used) / total))
                        Rectangle().fill(tc(0.10, 0.65, 0.95))
                            .frame(width: g.size.width * CGFloat(Double(u.purgeable) / total))
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                legend(tc(0.58, 0.6, 0.85), tr("已用", "Used"), u.used)
                legend(tc(0.10, 0.65, 0.95), tr("可清除", "Purgeable"), u.purgeable)
                legend(Color.secondary.opacity(0.4), tr("空闲", "Free"), u.free)
            }
        }
    }

    private func legend(_ color: Color, _ title: String, _ bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(formatSize(bytes))")
                .font(.caption.monospacedDigit())
        }
    }
}
