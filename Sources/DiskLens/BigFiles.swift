import SwiftUI
import AppKit

// 大文件排行榜:当前文件夹整棵子树里最大的文件。
// 直接使用内存里的扫描结果(≥2MB 的文件),所以切换标签是瞬间的。

struct BigFile: Identifiable {
    let node: Node
    let category: Category
    var id: UUID { node.id }
}

extension ViewModel {
    func refreshBigFiles() {
        guard viewMode == .big, let cur = current else {
            bigFiles = []
            return
        }
        let filter = bigFilter
        var out: [BigFile] = []
        func walk(_ n: Node, inApp: Bool) {
            for c in n.children where !c.isAggregate {
                if c.isDir {
                    walk(c, inApp: inApp || c.url.pathExtension.lowercased() == "app")
                } else {
                    let cat = Category.of(c.url, inApp: inApp)
                    if filter == nil || filter == cat { out.append(BigFile(node: c, category: cat)) }
                }
            }
        }
        walk(cur, inApp: cur.isInsideApp)
        bigFiles = Array(out.sorted { $0.node.size > $1.node.size }.prefix(bigLimit))
    }
}

struct BigFileListView: View {
    @ObservedObject var vm: ViewModel
    let node: Node

    var body: some View {
        let total = vm.bigFiles.reduce(Int64(0)) { $0 + $1.node.size }
        let maxSize = max(vm.bigFiles.first?.node.size ?? 1, 1)

        VStack(spacing: 0) {
            // 筛选
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

                Picker("", selection: $vm.bigLimit) {
                    Text(tr("前 50 个", "Top 50")).tag(50)
                    Text(tr("前 100 个", "Top 100")).tag(100)
                    Text(tr("前 200 个", "Top 200")).tag(200)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Spacer()
                Text(tr("合计 \(formatSize(total))", "Total \(formatSize(total))"))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if vm.bigFiles.isEmpty {
                Text(tr("这里没有 2MB 以上的文件", "No files of 2 MB or more here"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vm.bigFiles.enumerated()), id: \.element.id) { i, bf in
                            row(rank: i + 1, bf, maxSize: maxSize)
                        }
                    }
                }
                Text(tr("只统计 2MB 以上的文件;路径相对于当前文件夹。",
                        "Only files of 2 MB or more are ranked; paths are relative to the current folder."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
    }

    private func relativeDir(_ n: Node) -> String {
        let base = node.url.standardizedFileURL.path
        let dir = n.url.deletingLastPathComponent().standardizedFileURL.path
        if dir == base { return "." }
        if dir.hasPrefix(base + "/") { return String(dir.dropFirst(base.count + 1)) }
        return (dir as NSString).abbreviatingWithTildeInPath
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
                Text(relativeDir(c))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
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
