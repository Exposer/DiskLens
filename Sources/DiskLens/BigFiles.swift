import SwiftUI
import AppKit

// 大文件排行榜:当前文件夹整棵子树里最大的文件,可以按“多久没修改过”筛选。
// 直接使用内存里的扫描结果(≥2MB 的文件),所以切换标签是瞬间的。

enum BigSort: CaseIterable, Hashable {
    case size, oldest

    var title: String {
        switch self {
        case .size: return tr("按大小", "By size")
        case .oldest: return tr("最久未修改在前", "Oldest first")
        }
    }
}

struct BigFile: Identifiable {
    let node: Node
    let category: Category
    var id: UUID { node.id }
    var mod: Date? { node.mod }
}

extension ViewModel {
    func refreshBigFiles() {
        guard viewMode == .big, let cur = current else {
            bigFiles = []
            return
        }
        let filter = bigFilter
        // 只保留“超过 N 个月没修改过”的文件;没有修改时间的文件(旧数据)在筛选时排除
        let cutoff: Date? = bigMinAgeMonths > 0
            ? Calendar.current.date(byAdding: .month, value: -bigMinAgeMonths, to: Date())
            : nil
        var out: [BigFile] = []
        func walk(_ n: Node, inApp: Bool) {
            for c in n.children where !c.isAggregate {
                if c.isDir {
                    walk(c, inApp: inApp || c.url.pathExtension.lowercased() == "app")
                } else {
                    let cat = Category.of(c.url, inApp: inApp)
                    if let f = filter, f != cat { continue }
                    if let cutoff {
                        guard let m = c.mod, m < cutoff else { continue }
                    }
                    out.append(BigFile(node: c, category: cat))
                }
            }
        }
        walk(cur, inApp: cur.isInsideApp)

        switch bigSort {
        case .size:
            out.sort { $0.node.size > $1.node.size }
        case .oldest:
            out.sort {
                let a = $0.mod ?? .distantFuture
                let b = $1.mod ?? .distantFuture
                return a == b ? $0.node.size > $1.node.size : a < b
            }
        }
        bigFiles = Array(out.prefix(bigLimit))
    }
}

struct BigFileListView: View {
    @ObservedObject var vm: ViewModel
    let node: Node

    var body: some View {
        let total = vm.bigFiles.reduce(Int64(0)) { $0 + $1.node.size }
        let maxSize = max(vm.bigFiles.map { $0.node.size }.max() ?? 1, 1)

        VStack(spacing: 0) {
            filters(total: total)
            Divider()

            if vm.bigFiles.isEmpty {
                Text(vm.bigMinAgeMonths > 0
                     ? tr("没有符合条件的文件(2MB 以上、且在这段时间内没修改过)",
                          "No matching files (2 MB or more and not modified in that time)")
                     : tr("这里没有 2MB 以上的文件", "No files of 2 MB or more here"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vm.bigFiles.enumerated()), id: \.element.id) { i, bf in
                            row(rank: i + 1, bf, maxSize: maxSize)
                        }
                    }
                }
                Text(tr("只统计 2MB 以上的文件;路径相对于当前文件夹;时间是文件的最后修改时间。",
                        "Only files of 2 MB or more are ranked; paths are relative to the current folder; dates are last-modified times."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
    }

    private func filters(total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("", selection: $vm.bigFilter) {
                    Text(tr("全部类型", "All types")).tag(Category?.none)
                    ForEach(Category.allCases) { cat in
                        Text(cat.title).tag(Category?.some(cat))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Picker("", selection: $vm.bigMinAgeMonths) {
                    Text(tr("不限修改时间", "Any modified date")).tag(0)
                    Text(tr("超过 3 个月没修改", "Not modified in 3+ months")).tag(3)
                    Text(tr("超过 6 个月没修改", "Not modified in 6+ months")).tag(6)
                    Text(tr("超过 1 年没修改", "Not modified in 1+ year")).tag(12)
                    Text(tr("超过 2 年没修改", "Not modified in 2+ years")).tag(24)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 8) {
                Picker("", selection: $vm.bigSort) {
                    ForEach(BigSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Picker("", selection: $vm.bigLimit) {
                    Text(tr("前 50 个", "Top 50")).tag(50)
                    Text(tr("前 100 个", "Top 100")).tag(100)
                    Text(tr("前 200 个", "Top 200")).tag(200)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Spacer()
                Text(tr("共 \(vm.bigFiles.count) 个 · \(formatSize(total))",
                        "\(vm.bigFiles.count) files · \(formatSize(total))"))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func relativeDir(_ n: Node) -> String {
        let base = node.url.standardizedFileURL.path
        let dir = n.url.deletingLastPathComponent().standardizedFileURL.path
        if dir == base { return "." }
        if dir.hasPrefix(base + "/") { return String(dir.dropFirst(base.count + 1)) }
        return (dir as NSString).abbreviatingWithTildeInPath
    }

    /// 超过一年没修改的显示成橙色,提醒这是“很久没碰过”的文件
    private func ageColor(_ d: Date) -> Color {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        return d < oneYearAgo ? .orange : .secondary
    }

    private func row(rank: Int, _ bf: BigFile, maxSize: Int64) -> some View {
        let c = bf.node
        let inCollector = vm.isCollected(c)
        return HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
            Image(systemName: inCollector ? "tray.full.fill" : bf.category.icon)
                .foregroundStyle(inCollector ? appAccent : bf.category.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.displayName).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(relativeDir(c))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    if let m = bf.mod {
                        Text("·").foregroundStyle(.secondary)
                        Text(relativeDate(m))
                            .lineLimit(1)
                            .foregroundStyle(ageColor(m))
                            .help(tr("最后修改于 \(formatDate(m))", "Last modified \(formatDate(m))"))
                    }
                }
                .font(.caption2)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(bf.category.color)
                            .frame(width: g.size.width * CGFloat(Double(c.size) / Double(maxSize)))
                    }
                }
                .frame(height: 4)
            }
            Text(formatSize(c.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            Button { vm.collect(c) } label: { Image(systemName: "tray.and.arrow.down") }
                .buttonStyle(.borderless)
                .help(tr("加入收集器", "Add to Collector"))
            Button { vm.reveal(c) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(tr("在 Finder 中显示", "Reveal in Finder"))
            Button { vm.pendingTrash = c } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help(tr("移到废纸篓", "Move to Trash"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(c.url.path)
        .contextMenu {
            Button(tr("加入收集器", "Add to Collector")) { vm.collect(c) }
            Button(tr("在 Finder 中显示", "Reveal in Finder")) { vm.reveal(c) }
            Button(tr("移到废纸篓…", "Move to Trash…"), role: .destructive) { vm.pendingTrash = c }
        }
    }
}
