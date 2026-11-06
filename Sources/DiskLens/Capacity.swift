import SwiftUI
import AppKit

/// 启动磁盘的容量分解:已用 / 可清除 / 可用
struct VolumeUsage {
    let total: Int64
    let used: Int64        // 实际占用,不含可清除部分
    let purgeable: Int64   // 系统在空间不足时会自动清理的内容(缓存、本地快照、可重新下载的文件等)
    let free: Int64        // 立即可用的空闲空间

    /// 系统“实际可用”= 空闲 + 可清除(和访达、储存空间设置里显示的“可用”一致)
    var available: Int64 { free + purgeable }

    static func read(_ path: String = "/") -> VolumeUsage? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let v = try? url.resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity,
              let raw = v.volumeAvailableCapacity,
              let important = v.volumeAvailableCapacityForImportantUsage else { return nil }
        let t = Int64(total)
        let free = Int64(raw)
        let purgeable = max(0, important - free)
        let used = max(0, t - free - purgeable)
        return VolumeUsage(total: t, used: used, purgeable: purgeable, free: free)
    }
}

struct CapacityBar: View {
    /// 窗口很窄时用紧凑版:一条短的容量条 + 一个“可用”数字,不再显示三个图例
    var compact = false
    @State private var usage = VolumeUsage.read()
    @State private var showInfo = false

    private var usedColor: Color { tc(0.58, 0.6, 0.85) }
    private var purgeColor: Color { tc(0.10, 0.65, 0.95) }
    private var freeColor: Color { Color.secondary.opacity(0.25) }

    var body: some View {
        HStack(spacing: 12) {
            if let u = usage {
                bar(u)
                    .frame(width: compact ? 110 : 220, height: 10)
                if compact {
                    Text(tr("可用 \(formatSize(u.available))", "\(formatSize(u.available)) available"))
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    legend(color: usedColor, title: tr("已用", "Used"), bytes: u.used)
                    legend(color: purgeColor, title: tr("可清除", "Purgeable"), bytes: u.purgeable)
                    legend(color: freeColor, title: tr("空闲", "Free"), bytes: u.free)
                }
                Button {
                    showInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help(tr("什么是可清除空间?", "What is purgeable space?"))
                .popover(isPresented: $showInfo, arrowEdge: .top) { info(u) }
            } else {
                Text(tr("无法读取磁盘容量", "Unable to read disk capacity"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            usage = VolumeUsage.read()
        }
    }

    private func bar(_ u: VolumeUsage) -> some View {
        GeometryReader { g in
            let total = Double(max(u.total, 1))
            let wUsed = g.size.width * CGFloat(Double(u.used) / total)
            let wPurge = g.size.width * CGFloat(Double(u.purgeable) / total)
            ZStack(alignment: .leading) {
                Capsule().fill(freeColor)
                HStack(spacing: 0) {
                    Rectangle().fill(usedColor).frame(width: wUsed)
                    Rectangle().fill(purgeColor).frame(width: wPurge)
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule())
            }
        }
    }

    private func legend(color: Color, title: String, bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(formatSize(bytes))")
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .fixedSize()          // 宽度不够时由上层换成紧凑版,而不是把文字挤成竖排
        }
    }

    private func info(_ u: VolumeUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("可清除空间", "Purgeable Space")).font(.headline)
            Text(tr("这部分空间现在被占用,但 macOS 在磁盘不足时会自动释放,比如可重新下载的 iCloud 文件、系统缓存和本地 Time Machine 快照。你不需要手动清理它。",
                    "This space is in use now, but macOS frees it automatically when the disk runs low — for example re-downloadable iCloud files, system caches and local Time Machine snapshots. You don't need to clean it up manually."))
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Group {
                row(tr("容量", "Capacity"), u.total)
                row(tr("已用(不可自动释放)", "Used (not auto-reclaimable)"), u.used)
                row(tr("可清除", "Purgeable"), u.purgeable)
                row(tr("空闲", "Free"), u.free)
                row(tr("系统视角的可用 (空闲 + 可清除)", "Available to the system (Free + Purgeable)"), u.available)
            }
            Divider()
            Text(tr("扫描到的大文件不一定算在「已用」里,可清除部分的内容 DiskLens 看不到,所以扫描总和可能小于「已用」。",
                    "Purgeable content is invisible to a file scan, so the scanned total can be smaller than \"Used\"."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(tr("打开「储存空间」设置", "Open Storage Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func row(_ title: String, _ bytes: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(formatSize(bytes)).monospacedDigit()
        }
        .font(.callout)
    }
}
