import SwiftUI
import AppKit
import UserNotifications

// 磁盘快满时提醒:每分钟检查一次启动磁盘的“可用空间”(空闲 + 可清除,和访达、系统设置里的「可用」一致),
// 低于设定的阈值时,在窗口顶部显示提示条;如果 DiskLens 在后台,再发一条系统通知(最多每 6 小时一次)。

enum LowSpaceRule: String, CaseIterable, Identifiable {
    case off, gb10, gb20, gb50, gb100, pct10, pct15, pct20
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return tr("关闭提醒", "Off")
        case .gb10: return tr("可用不足 10 GB", "Below 10 GB")
        case .gb20: return tr("可用不足 20 GB", "Below 20 GB")
        case .gb50: return tr("可用不足 50 GB", "Below 50 GB")
        case .gb100: return tr("可用不足 100 GB", "Below 100 GB")
        case .pct10: return tr("可用不足 10%", "Below 10%")
        case .pct15: return tr("可用不足 15%", "Below 15%")
        case .pct20: return tr("可用不足 20%", "Below 20%")
        }
    }

    func isLow(_ u: VolumeUsage) -> Bool {
        let gb: Int64 = 1_000_000_000      // 和访达一样用十进制 GB
        let frac = Double(u.available) / Double(max(u.total, 1))
        switch self {
        case .off: return false
        case .gb10: return u.available < 10 * gb
        case .gb20: return u.available < 20 * gb
        case .gb50: return u.available < 50 * gb
        case .gb100: return u.available < 100 * gb
        case .pct10: return frac < 0.10
        case .pct15: return frac < 0.15
        case .pct20: return frac < 0.20
        }
    }
}

extension Prefs {
    static var lowRule: LowSpaceRule = {
        if let s = UserDefaults.standard.string(forKey: "lowRule"), let r = LowSpaceRule(rawValue: s) { return r }
        return .pct10
    }() {
        didSet { UserDefaults.standard.set(lowRule.rawValue, forKey: "lowRule") }
    }

    static var lowNotify: Bool = {
        UserDefaults.standard.object(forKey: "lowNotify") as? Bool ?? true
    }() {
        didSet { UserDefaults.standard.set(lowNotify, forKey: "lowNotify") }
    }
}

/// 系统通知。只有打包成 .app 并有 bundle id 时才能用;用 `swift run` 直接运行时调用系统通知会崩溃,所以先检查。
enum Notifier {
    static var available: Bool {
        Bundle.main.bundlePath.hasSuffix(".app") && Bundle.main.bundleIdentifier != nil
    }

    static func requestAuthIfNeeded() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "disklens.lowspace", content: c, trigger: nil))
    }
}

extension ViewModel {
    func startDiskMonitor() {
        guard diskTimer == nil else { return }
        if Prefs.lowRule != .off && Prefs.lowNotify { Notifier.requestAuthIfNeeded() }
        checkDiskSpace()
        diskTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDiskSpace() }
        }
    }

    /// 检查一次;设置改变后也会马上调用
    func checkDiskSpace() {
        guard Prefs.lowRule != .off, let u = VolumeUsage.read(), Prefs.lowRule.isLow(u) else {
            lowSpace = nil
            lowSpaceDismissed = false      // 空间恢复后,下次再不足会重新提醒
            return
        }
        let wasLow = lowSpace != nil
        lowSpace = u
        if !wasLow {
            lowSpaceDismissed = false
            notifyLowSpace(u)
        }
    }

    private func notifyLowSpace(_ u: VolumeUsage) {
        // 窗口在前台时已经有提示条了,只在 DiskLens 位于后台时发系统通知;最多每 6 小时一次
        guard Prefs.lowNotify, Notifier.available, !NSApplication.shared.isActive else { return }
        let key = "lastLowNotify"
        let now = Date().timeIntervalSince1970
        guard now - UserDefaults.standard.double(forKey: key) > 6 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: key)
        let pct = Double(u.available) / Double(max(u.total, 1)) * 100
        Notifier.post(
            title: tr("磁盘空间不足", "Low disk space"),
            body: tr("只剩 \(formatSize(u.available)) 可用(\(String(format: "%.0f", pct))%)。打开 DiskLens 找出占用最多的内容。",
                     "Only \(formatSize(u.available)) available (\(String(format: "%.0f", pct))%). Open DiskLens to find what is using the most space."))
    }
}

// MARK: - 状态栏里的提醒设置菜单

struct LowSpaceMenu: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        Menu {
            Section(tr("可用空间低于…时提醒", "Alert when available space is below…")) {
                ForEach(LowSpaceRule.allCases) { r in
                    Button {
                        Prefs.lowRule = r
                        if r != .off && Prefs.lowNotify { Notifier.requestAuthIfNeeded() }
                        vm.checkDiskSpace()
                        vm.objectWillChange.send()
                    } label: {
                        if Prefs.lowRule == r {
                            Label(r.title, systemImage: "checkmark")
                        } else {
                            Text(r.title)
                        }
                    }
                }
            }
            Divider()
            Toggle(isOn: Binding(
                get: { Prefs.lowNotify },
                set: { on in
                    Prefs.lowNotify = on
                    if on { Notifier.requestAuthIfNeeded() }
                    vm.objectWillChange.send()
                })
            ) {
                Text(Notifier.available
                     ? tr("DiskLens 在后台时发系统通知", "Send a system notification when DiskLens is in the background")
                     : tr("系统通知(仅打包后的 App 可用)", "System notification (packaged app only)"))
            }
            .disabled(!Notifier.available)
        } label: {
            Label(tr("空间提醒", "Space Alert"),
                  systemImage: Prefs.lowRule == .off ? "bell.slash" : "bell")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
        .help(tr("磁盘「可用空间」(空闲 + 可清除)低于设定值时提醒你",
                 "Alerts you when the disk's available space (free + purgeable) drops below the chosen limit"))
    }
}
