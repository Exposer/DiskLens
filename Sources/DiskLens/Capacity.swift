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
    @State private var usage = VolumeUsage.read()
    @State private var showInfo = false

    private let usedColor = Color(hue: 0.58, saturation: 0.6, brightness: 0.85)
    private let purgeColor = Color(hue: 0.10, saturation: 0.65, brightness: 0.95)
    private let freeColor = Color.secondary.opacity(0.25)

    var body: some View {
        HStack(spacing: 12) {
            if let u = usage {
                bar(u)
                    .frame(width: 220, height: 10)
                legend(color: usedColor, title: "已用", bytes: u.used)
                legend(color: purgeColor, title: "可清除", bytes: u.purgeable)
                legend(color: freeColor, title: "空闲", bytes: u.free)
                Button {
                    showInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("什么是可清除空间?")
                .popover(isPresented: $showInfo, arrowEdge: .top) { info(u) }
            } else {
                Text("无法读取磁盘容量").font(.caption).foregroundStyle(.secondary)
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
        }
    }

    private func info(_ u: VolumeUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可清除空间").font(.headline)
            Text("这部分空间现在被占用,但 macOS 在磁盘不足时会自动释放,比如可重新下载的 iCloud 文件、系统缓存和本地 Time Machine 快照。你不需要手动清理它。")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Group {
                row("容量", u.total)
                row("已用(不可自动释放)", u.used)
                row("可清除", u.purgeable)
                row("空闲", u.free)
                row("系统视角的可用 (空闲 + 可清除)", u.available)
            }
            Divider()
            Text("扫描到的大文件不一定算在「已用」里,可清除部分的内容 DiskLens 看不到,所以扫描总和可能小于「已用」。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("打开「储存空间」设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
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
