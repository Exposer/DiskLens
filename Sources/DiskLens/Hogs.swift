import SwiftUI
import AppKit

// 常见占用大户:Xcode、Homebrew、Docker 等已知会悄悄变大的位置。
// 大小是单独统计的,不依赖当前的扫描结果。

enum HogLevel {
    case safe, caution, info

    var title: String {
        switch self {
        case .safe: return tr("可清理", "Safe to clean")
        case .caution: return tr("谨慎", "Be careful")
        case .info: return tr("仅提示", "Info")
        }
    }

    var color: Color {
        switch self {
        case .safe: return Color(hue: 0.38, saturation: 0.6, brightness: 0.72)
        case .caution: return Color(hue: 0.09, saturation: 0.75, brightness: 0.92)
        case .info: return Color.secondary
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield"
        case .caution: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }
}

struct HogDef: Sendable {
    let id: String
    let path: String              // 相对于个人文件夹
    let zh: String
    let en: String
    let descZh: String
    let descEn: String
    let level: HogLevel
    var collectable = true        // false = 不能直接放进收集器,请用命令或在对应 App 里处理
    var command: String? = nil    // 推荐的清理命令
}

struct HogItem: Identifiable, Sendable {
    let def: HogDef
    let url: URL
    var size: Int64
    var id: String { def.id }
    var title: String { tr(def.zh, def.en) }
    var desc: String { tr(def.descZh, def.descEn) }
}

enum HogCatalog {
    static let all: [HogDef] = [
        HogDef(id: "xcode-dd", path: "Library/Developer/Xcode/DerivedData",
               zh: "Xcode 编译缓存 (DerivedData)", en: "Xcode Build Cache (DerivedData)",
               descZh: "编译产生的中间文件,删除后 Xcode 下次编译会自动重新生成。",
               descEn: "Intermediate build products. Xcode regenerates them on the next build.",
               level: .safe),
        HogDef(id: "xcode-devsupport", path: "Library/Developer/Xcode/iOS DeviceSupport",
               zh: "Xcode 设备调试支持文件", en: "Xcode iOS Device Support",
               descZh: "连接真机调试时生成的符号文件,删除后再次连接设备会重新下载。",
               descEn: "Symbol files created when debugging on a device. Re-downloaded when you connect it again.",
               level: .safe),
        HogDef(id: "xcode-archives", path: "Library/Developer/Xcode/Archives",
               zh: "Xcode 归档 (Archives)", en: "Xcode Archives",
               descZh: "发布用的归档包。删除后无法再用它们符号化崩溃日志,确认不再需要再清理。",
               descEn: "Release archives. Without them you can't symbolicate old crash logs; clean only if you no longer need them.",
               level: .caution),
        HogDef(id: "coresim", path: "Library/Developer/CoreSimulator",
               zh: "iOS 模拟器", en: "iOS Simulators",
               descZh: "不要直接删文件夹。建议用命令清理不可用的模拟器。",
               descEn: "Don't delete the folder directly. Use the command to remove unavailable simulators.",
               level: .caution, collectable: false, command: "xcrun simctl delete unavailable"),
        HogDef(id: "brew", path: "Library/Caches/Homebrew",
               zh: "Homebrew 下载缓存", en: "Homebrew Download Cache",
               descZh: "已下载的安装包和旧版本,可以安全清理。",
               descEn: "Downloaded bottles and old versions. Safe to clean.",
               level: .safe, command: "brew cleanup -s"),
        HogDef(id: "npm", path: ".npm",
               zh: "npm 缓存", en: "npm Cache",
               descZh: "npm 下载过的包缓存,删除后会按需重新下载。",
               descEn: "Cached packages. They are downloaded again when needed.",
               level: .safe, command: "npm cache clean --force"),
        HogDef(id: "yarn", path: "Library/Caches/Yarn",
               zh: "Yarn 缓存", en: "Yarn Cache",
               descZh: "Yarn 的包缓存,可以安全清理。",
               descEn: "Yarn's package cache. Safe to clean.",
               level: .safe, command: "yarn cache clean"),
        HogDef(id: "pnpm", path: "Library/pnpm",
               zh: "pnpm 全局存储", en: "pnpm Store",
               descZh: "各项目通过硬链接共享这里的包。建议用命令清理未被引用的部分。",
               descEn: "Projects share packages here via hard links. Prefer pruning unreferenced packages with the command.",
               level: .caution, collectable: false, command: "pnpm store prune"),
        HogDef(id: "pods", path: "Library/Caches/CocoaPods",
               zh: "CocoaPods 缓存", en: "CocoaPods Cache",
               descZh: "下载过的 Pod 缓存,可以安全清理。",
               descEn: "Downloaded pods. Safe to clean.",
               level: .safe),
        HogDef(id: "gradle", path: ".gradle/caches",
               zh: "Gradle 缓存", en: "Gradle Cache",
               descZh: "依赖和构建缓存,删除后下次构建会重新下载。",
               descEn: "Dependency and build caches. Downloaded again on the next build.",
               level: .safe),
        HogDef(id: "pip", path: "Library/Caches/pip",
               zh: "pip 缓存", en: "pip Cache",
               descZh: "Python 包的下载缓存,可以安全清理。",
               descEn: "Cached Python packages. Safe to clean.",
               level: .safe, command: "pip cache purge"),
        HogDef(id: "cargo", path: ".cargo/registry",
               zh: "Cargo 注册表缓存", en: "Cargo Registry",
               descZh: "Rust 依赖的下载缓存,删除后会按需重新下载。",
               descEn: "Downloaded Rust crates. Fetched again when needed.",
               level: .safe),
        HogDef(id: "docker", path: "Library/Containers/com.docker.docker",
               zh: "Docker 数据", en: "Docker Data",
               descZh: "镜像、容器和数据卷都在这里的一个磁盘映像里。请用 docker 命令清理,不要直接删文件夹。",
               descEn: "Images, containers and volumes live in a disk image here. Clean with the docker command, not by deleting the folder.",
               level: .caution, collectable: false, command: "docker system prune -a"),
        HogDef(id: "caches", path: "Library/Caches",
               zh: "应用缓存 (~/Library/Caches)", en: "App Caches (~/Library/Caches)",
               descZh: "各应用的缓存,应用会按需重建。包含上面 Homebrew、Yarn、pip 等条目,统计会重叠。",
               descEn: "Per-app caches, rebuilt on demand. Includes Homebrew, Yarn, pip and others listed here, so totals overlap.",
               level: .safe),
        HogDef(id: "logs", path: "Library/Logs",
               zh: "日志", en: "Logs",
               descZh: "应用和系统生成的日志,可以安全清理。",
               descEn: "Logs written by apps and the system. Safe to clean.",
               level: .safe),
        HogDef(id: "ios-backup", path: "Library/Application Support/MobileSync/Backup",
               zh: "iPhone / iPad 本地备份", en: "iPhone / iPad Backups",
               descZh: "设备的本地备份,往往一个就几十 GB。确认不再需要后可以删除。",
               descEn: "Local device backups, often tens of GB each. Delete once you no longer need them.",
               level: .caution),
        HogDef(id: "trash", path: ".Trash",
               zh: "废纸篓", en: "Trash",
               descZh: "清倒废纸篓后才会真正释放空间:在 Finder 中选择「清倒废纸篓」。",
               descEn: "Space is only freed after emptying it: choose Empty Trash in Finder.",
               level: .info, collectable: false),
        HogDef(id: "downloads", path: "Downloads",
               zh: "下载", en: "Downloads",
               descZh: "安装包、压缩包常常堆在这里,请自己检查一遍。",
               descEn: "Installers and archives pile up here. Take a look yourself.",
               level: .info, collectable: false),
        HogDef(id: "messages", path: "Library/Messages/Attachments",
               zh: "信息附件", en: "Messages Attachments",
               descZh: "信息 App 里收发的图片和文件,请在「信息」里管理。",
               descEn: "Photos and files from Messages. Manage them in the Messages app.",
               level: .info, collectable: false),
        HogDef(id: "photos", path: "Pictures/Photos Library.photoslibrary",
               zh: "照片图库", en: "Photos Library",
               descZh: "请在「照片」App 里管理,不要直接动这个文件。",
               descEn: "Manage it in the Photos app; don't touch the file directly.",
               level: .info, collectable: false)
    ]
}

/// child 是否等于 parent,或位于 parent 之内
func urlIsInside(_ child: URL, of parent: URL) -> Bool {
    let c = child.standardizedFileURL.path
    let p = parent.standardizedFileURL.path
    return c == p || c.hasPrefix(p.hasSuffix("/") ? p : p + "/")
}

enum HogScanner {
    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let en = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        let keySet = Set(keys)
        var finished = false
        while !finished {
            autoreleasepool {
                guard let u = en.nextObject() as? URL else { finished = true; return }
                guard let v = try? u.resourceValues(forKeys: keySet), v.isRegularFile == true else { return }
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

extension ViewModel {
    func refreshHogs() {
        guard !hogsLoading else { return }
        hogsLoading = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task.detached(priority: .utility) { [weak self] in
            let fm = FileManager.default
            let defs = HogCatalog.all.filter { fm.fileExists(atPath: home.appendingPathComponent($0.path).path) }
            var results = [HogItem?](repeating: nil, count: defs.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: defs.count) { i in
                let url = home.appendingPathComponent(defs[i].path)
                let item = HogItem(def: defs[i], url: url, size: HogScanner.size(of: url))
                lock.lock(); results[i] = item; lock.unlock()
            }
            let items = results.compactMap { $0 }.filter { $0.size > 0 }.sorted { $0.size > $1.size }
            await MainActor.run {
                self?.hogs = items
                self?.hogsLoading = false
            }
        }
    }

    /// 把一个占用大户包装成节点,以便放进收集器 / 在 Finder 中显示
    func node(for item: HogItem) -> Node {
        Node(url: item.url, name: item.title, isDir: true, size: item.size)
    }
}

// MARK: - 列表

struct HogListView: View {
    @ObservedObject var vm: ViewModel

    /// 可放进收集器的“可清理”项,去掉被其他项包含的(避免重复计算)
    private var safeItems: [HogItem] {
        let c = vm.hogs.filter { $0.def.level == .safe && $0.def.collectable }
        return c.filter { it in
            !c.contains { o in o.id != it.id && urlIsInside(it.url, of: o.url) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.hogsLoading && vm.hogs.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(tr("正在统计…", "Measuring…")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.hogs.isEmpty {
                Text(tr("没有发现常见的占用大户", "No common space hogs found"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.hogs) { item in
                            row(item)
                            Divider()
                        }
                    }
                }
                Text(tr("没有「完全磁盘访问权限」时,部分位置可能统计不到。",
                        "Some locations may be missing without Full Disk Access."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .onAppear { if vm.hogs.isEmpty { vm.refreshHogs() } }
    }

    private var header: some View {
        let total = safeItems.reduce(Int64(0)) { $0 + $1.size }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("可安全清理合计", "Safe to clean in total")).font(.callout)
                Spacer()
                Text(formatSize(total)).font(.headline.monospacedDigit())
            }
            HStack {
                Button {
                    for it in safeItems { vm.collect(vm.node(for: it)) }
                } label: {
                    Label(tr("全部「可清理」加入收集器", "Add all “safe” items to Collector"),
                          systemImage: "tray.and.arrow.down")
                }
                .disabled(safeItems.isEmpty)
                Spacer()
                Button {
                    vm.refreshHogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(vm.hogsLoading)
                .help(tr("重新统计", "Measure again"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ item: HogItem) -> some View {
        let node = vm.node(for: item)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.def.level.icon)
                .foregroundStyle(item.def.level.color)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title).lineLimit(1)
                    Text(item.def.level.title)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(item.def.level.color.opacity(0.2)))
                        .foregroundStyle(item.def.level.color)
                }
                Text(item.desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let cmd = item.def.command {
                    HStack(spacing: 6) {
                        Text(cmd)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("复制命令", "Copy command"))
                    }
                }
            }
            Spacer(minLength: 4)
            Text(formatSize(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button { vm.reveal(node) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(tr("在 Finder 中显示", "Reveal in Finder"))
            if item.def.collectable {
                Button { vm.collect(node) } label: {
                    Image(systemName: vm.isCollected(node) ? "tray.full.fill" : "tray.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help(tr("加入收集器", "Add to Collector"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
