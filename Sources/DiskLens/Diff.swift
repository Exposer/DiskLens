import SwiftUI
import AppKit

// 对比扫描:把当前的扫描结果和之前保存的某次扫描逐层对比,看磁盘是被什么撑大(或腾出来)的。
// 文件夹的大小变化是精确的;文件只有 ≥2MB 的才会出现在扫描树里,所以文件级别的变化只覆盖这部分。

struct DiffNode: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isDir: Bool
    let isOther: Bool        // “其他(小文件等)”汇总行
    let old: Int64
    let new: Int64
    var children: [DiffNode]
    var delta: Int64 { new - old }
    /// List 的层级展示需要:没有子项时为 nil
    var kids: [DiffNode]? { children.isEmpty ? nil : children }
}

enum FileChangeKind {
    case added, removed, grown, shrunk

    var title: String {
        switch self {
        case .added: return tr("新增", "New")
        case .removed: return tr("已删除", "Removed")
        case .grown: return tr("增长", "Grew")
        case .shrunk: return tr("减少", "Shrunk")
        }
    }
}

struct FileChange: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let old: Int64
    let new: Int64
    var delta: Int64 { new - old }
    var kind: FileChangeKind {
        if old == 0 { return .added }
        if new == 0 { return .removed }
        return delta > 0 ? .grown : .shrunk
    }
}

struct DiffResult {
    let oldDate: Date
    let newDate: Date?
    let oldTotal: Int64
    let newTotal: Int64
    let tree: [DiffNode]
    let files: [FileChange]
    var delta: Int64 { newTotal - oldTotal }
    var addedCount: Int { files.filter { $0.kind == .added }.count }
    var removedCount: Int { files.filter { $0.kind == .removed }.count }
    var maxAbsDelta: Int64 { max(tree.map { abs($0.delta) }.max() ?? 1, 1) }
}

enum DiffEngine {
    /// 小于这个变化量的节点不显示,避免满屏噪声
    static let threshold: Int64 = 1024 * 1024

    static func compute(old: Node, oldDate: Date, new: Node, newDate: Date?) -> DiffResult {
        var files: [FileChange] = []
        let root = diff(old, new, files: &files)
        files.sort { abs($0.delta) > abs($1.delta) }
        return DiffResult(oldDate: oldDate, newDate: newDate,
                          oldTotal: old.size, newTotal: new.size,
                          tree: root?.children ?? [], files: files)
    }

    /// 把同一路径上的旧节点和新节点比较;任何一边可以缺失(新增 / 已删除)
    private static func diff(_ o: Node?, _ n: Node?, files: inout [FileChange]) -> DiffNode? {
        guard let ref = n ?? o else { return nil }
        let os = o?.size ?? 0
        let ns = n?.size ?? 0

        if !ref.isDir {
            guard abs(ns - os) >= threshold else { return nil }
            files.append(FileChange(name: ref.name, url: ref.url, old: os, new: ns))
            return DiffNode(name: ref.name, url: ref.url, isDir: false, isOther: false,
                            old: os, new: ns, children: [])
        }

        // 目录:按名字合并两边的子节点(忽略“小文件”合并节点)
        let oc = Dictionary((o?.children ?? []).filter { !$0.isAggregate }.map { ($0.name, $0) },
                            uniquingKeysWith: { a, _ in a })
        let nc = Dictionary((n?.children ?? []).filter { !$0.isAggregate }.map { ($0.name, $0) },
                            uniquingKeysWith: { a, _ in a })
        var kids: [DiffNode] = []
        for name in Set(oc.keys).union(nc.keys) {
            if let k = diff(oc[name], nc[name], files: &files) { kids.append(k) }
        }
        kids.sort { abs($0.delta) > abs($1.delta) }

        // 子项加起来不等于目录的变化量时,差额是被合并掉的小文件,补一行“其他”
        let kidOld = kids.reduce(Int64(0)) { $0 + $1.old }
        let kidNew = kids.reduce(Int64(0)) { $0 + $1.new }
        let restOld = os - kidOld
        let restNew = ns - kidNew
        if !kids.isEmpty, abs(restNew - restOld) >= threshold {
            kids.append(DiffNode(name: tr("其他(小文件等)", "Other (small items)"), url: ref.url,
                                 isDir: false, isOther: true, old: max(0, restOld), new: max(0, restNew),
                                 children: []))
        }

        if abs(ns - os) < threshold && kids.isEmpty { return nil }
        return DiffNode(name: ref.name, url: ref.url, isDir: true, isOther: false,
                        old: os, new: ns, children: kids)
    }
}

// MARK: - 窗口

struct DiffSheet: View {
    @ObservedObject var vm: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [ScanStore.HistoryEntry] = []
    @State private var selected: URL?
    @State private var result: DiffResult?
    @State private var loading = false
    @State private var failed = false
    @State private var tab = 0            // 0 = 文件夹层级, 1 = 文件变化
    @State private var fileFilter = 0     // 0 = 全部, 1 = 增长(含新增), 2 = 减少(含已删除)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Prefs.theme.bg)
        .onAppear(perform: loadEntries)
    }

    // MARK: 顶部:选择要对比的历史扫描

    private var header: some View {
        HStack(spacing: 10) {
            Text(tr("对比扫描", "Compare Scans")).font(.headline)
            Spacer()
            if !entries.isEmpty {
                Text(tr("和这次扫描对比:", "Compare with:")).font(.callout).foregroundStyle(.secondary)
                Picker("", selection: $selected) {
                    ForEach(entries) { e in
                        Text(formatDate(e.date) + " (" + relativeDate(e.date) + ")").tag(Optional(e.url))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: selected) { _ in compute() }
            }
            Button(tr("关闭", "Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Prefs.theme.bar)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.2.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                Text(tr("还没有可以对比的历史扫描", "No earlier scans to compare with yet"))
                    .font(.headline)
                Text(tr("DiskLens 会在每次完整扫描后保存一份历史快照(每个文件夹保留最近 \(ScanStore.maxHistory) 次)。再扫描一次这个文件夹,就能看到两次之间磁盘的变化。",
                        "DiskLens keeps a snapshot after every complete scan (the latest \(ScanStore.maxHistory) per folder). Scan this folder once more to see what changed in between."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loading {
            VStack(spacing: 10) {
                ProgressView()
                Text(tr("正在对比…", "Comparing…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if failed {
            Text(tr("读取这份历史快照失败,可能是它的格式太旧。", "Couldn't read this snapshot; its format may be too old."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = result {
            summary(r)
            Divider()
            Picker("", selection: $tab) {
                Text(tr("文件夹层级", "Folder hierarchy")).tag(0)
                Text(tr("单个文件", "Individual files")).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            .padding(.vertical, 8)
            Divider()
            if tab == 0 { hierarchy(r) } else { fileList(r) }
            Text(tr("只显示变化超过 1 MB 的项目;文件只覆盖 2 MB 以上的部分(更小的文件汇总在「其他」里)。红色 = 变大,绿色 = 变小。",
                    "Only changes over 1 MB are shown; files cover the 2 MB+ part (smaller ones are summed under “Other”). Red = grew, green = shrank."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }

    private func deltaText(_ d: Int64) -> String {
        (d >= 0 ? "+" : "−") + formatSize(abs(d))
    }

    private func deltaColor(_ d: Int64) -> Color {
        d > 0 ? Color(hue: 0.0, saturation: 0.65, brightness: 0.9)
              : Color(hue: 0.36, saturation: 0.6, brightness: 0.7)
    }

    private func summary(_ r: DiffResult) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("总大小变化", "Total change")).font(.caption).foregroundStyle(.secondary)
                Text(deltaText(r.delta))
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundStyle(deltaColor(r.delta))
                Text("\(formatSize(r.oldTotal)) → \(formatSize(r.newTotal))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("时间跨度", "Time span")).font(.caption).foregroundStyle(.secondary)
                Text(spanText(r)).font(.title3)
                Text(formatDate(r.oldDate) + " → " + (r.newDate.map { formatDate($0) } ?? "-"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("大文件(≥ 2 MB)", "Large files (≥ 2 MB)")).font(.caption).foregroundStyle(.secondary)
                Text(tr("新增 \(r.addedCount) · 删除 \(r.removedCount)",
                        "\(r.addedCount) new · \(r.removedCount) removed"))
                    .font(.title3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func spanText(_ r: DiffResult) -> String {
        guard let n = r.newDate else { return "-" }
        let secs = max(0, n.timeIntervalSince(r.oldDate))
        let days = Int(secs / 86400)
        if days >= 1 { return tr("\(days) 天", "\(days) day\(days == 1 ? "" : "s")") }
        let hours = Int(secs / 3600)
        if hours >= 1 { return tr("\(hours) 小时", "\(hours) hour\(hours == 1 ? "" : "s")") }
        return tr("不到 1 小时", "Under an hour")
    }

    // MARK: 文件夹层级

    private func hierarchy(_ r: DiffResult) -> some View {
        let maxAbs = r.maxAbsDelta
        return Group {
            if r.tree.isEmpty {
                Text(tr("两次扫描之间没有超过 1 MB 的变化。", "No changes over 1 MB between the two scans."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(r.tree, children: \.kids) { node in
                    nodeRow(node, maxAbs: maxAbs)
                }
                .listStyle(.inset)
            }
        }
    }

    private func nodeRow(_ node: DiffNode, maxAbs: Int64) -> some View {
        let frac = min(1.0, Double(abs(node.delta)) / Double(max(maxAbs, 1)))
        return HStack(spacing: 8) {
            Image(systemName: node.isOther ? "square.stack.3d.up" : (node.isDir ? "folder.fill" : "doc"))
                .foregroundStyle(node.isDir ? appAccent : Color.secondary)
                .frame(width: 18)
            Text(node.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(formatSize(node.old)) → \(formatSize(node.new))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(deltaText(node.delta))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(deltaColor(node.delta))
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .background(alignment: .leading) {
            GeometryReader { g in
                Rectangle()
                    .fill(deltaColor(node.delta).opacity(0.14))
                    .frame(width: g.size.width * CGFloat(frac))
            }
        }
        .help(node.url.path)
    }

    // MARK: 单个文件

    private func fileList(_ r: DiffResult) -> some View {
        let shown: [FileChange]
        switch fileFilter {
        case 1: shown = r.files.filter { $0.delta > 0 }
        case 2: shown = r.files.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }
        default: shown = r.files
        }
        return VStack(spacing: 0) {
            Picker("", selection: $fileFilter) {
                Text(tr("全部", "All")).tag(0)
                Text(tr("增长 / 新增", "Grew / New")).tag(1)
                Text(tr("减少 / 已删除", "Shrunk / Removed")).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            .padding(.vertical, 6)
            Divider()
            if shown.isEmpty {
                Text(tr("没有符合条件的文件", "No matching files"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown.prefix(500)) { f in
                    fileRow(f)
                }
                .listStyle(.inset)
            }
        }
    }

    private func fileRow(_ f: FileChange) -> some View {
        let exists = FileManager.default.fileExists(atPath: f.url.path)
        return HStack(spacing: 8) {
            Text(f.kind.title)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(deltaColor(f.delta).opacity(0.2)))
                .foregroundStyle(deltaColor(f.delta))
                .frame(minWidth: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).lineLimit(1).truncationMode(.middle)
                Text((f.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            Text("\(formatSize(f.old)) → \(formatSize(f.new))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(deltaText(f.delta))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(deltaColor(f.delta))
                .frame(minWidth: 90, alignment: .trailing)
            Button {
                vm.collect(Node(url: f.url, name: f.name, isDir: false, size: f.new))
            } label: { Image(systemName: "tray.and.arrow.down") }
                .buttonStyle(.borderless)
                .disabled(!exists || f.new == 0)
                .help(tr("加入收集器", "Add to Collector"))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([f.url])
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .disabled(!exists)
                .help(tr("在 Finder 中显示", "Reveal in Finder"))
        }
        .help(f.url.path)
    }

    // MARK: 加载与计算

    private func loadEntries() {
        guard let root = vm.root else { return }
        let cur = vm.scanDate
        // 排除“当前显示的这次扫描”自己的快照
        entries = ScanStore.history(for: root.url.path).filter { e in
            guard let cur else { return true }
            return abs(e.date.timeIntervalSince(cur)) > 1
        }
        selected = entries.first?.url
        compute()
    }

    private func compute() {
        guard let root = vm.root, let url = selected else { return }
        loading = true
        failed = false
        result = nil
        let newDate = vm.scanDate
        Task.detached(priority: .userInitiated) {
            guard let old = ScanStore.loadSnapshot(at: url) else {
                await MainActor.run { loading = false; failed = true }
                return
            }
            let r = DiffEngine.compute(old: old.root, oldDate: old.date, new: root, newDate: newDate)
            await MainActor.run {
                result = r
                loading = false
            }
        }
    }
}

// MARK: - 工具栏按钮

struct CompareButton: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        Button {
            vm.showDiff = true
        } label: {
            Label(tr("对比", "Compare"), systemImage: "plusminus.circle")
        }
        .disabled(vm.root == nil || vm.scanning)
        .help(tr("和之前的扫描对比,看磁盘是被什么撑大的", "Compare with an earlier scan to see what grew"))
    }
}
