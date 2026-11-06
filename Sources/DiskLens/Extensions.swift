import SwiftUI

// 按扩展名统计占用。
// 数据来自内存里的扫描结果:2MB 以上的文件按扩展名精确统计,更小的文件在扫描时已经合并,
// 所以单独列成一行“小文件”(它们的总大小是准确的,但没法再按扩展名拆分)。

enum TypeGrouping: CaseIterable, Hashable {
    case category, byExtension

    var title: String {
        switch self {
        case .category: return tr("按类别", "By category")
        case .byExtension: return tr("按扩展名", "By extension")
        }
    }
}

/// 文件的扩展名(小写,没有扩展名时为空字符串)
func extKey(_ url: URL) -> String { url.pathExtension.lowercased() }

func extLabel(_ key: String) -> String {
    key.isEmpty ? tr("(无扩展名)", "(no extension)") : ".\(key)"
}

struct ExtStat: Identifiable {
    let ext: String
    var bytes: Int64
    var count: Int
    var category: Category
    var id: String { ext }
    var label: String { extLabel(ext) }
}

/// 某个扩展名的累计大小和文件数
struct ExtTotal: Codable, Sendable {
    var bytes: Int64 = 0
    var count: Int = 0
    mutating func add(_ b: Int64) { bytes += b; count += 1 }
}

enum ExtStats {
    /// 统计某个文件夹的扩展名分布。
    /// 在扫描根目录上,使用扫描时记录的**精确**总表(包含所有小文件);
    /// 在子文件夹里,只能用扫描树统计 2MB 以上的文件,小文件合并成一行(exact = false)。
    static func stats(for cur: Node, root: Node?) -> (stats: [ExtStat], small: Int64, exact: Bool) {
        if let root, cur === root, let totals = root.extTotals {
            let list = totals.map { (key, t) -> ExtStat in
                let sample = URL(fileURLWithPath: key.isEmpty ? "/x" : "/x.\(key)")
                return ExtStat(ext: key, bytes: t.bytes, count: t.count,
                               category: Category.of(sample, inApp: false))
            }
            return (list.sorted { $0.bytes > $1.bytes }, 0, true)
        }
        let r = compute(cur)
        return (r.stats, r.small, false)
    }

    /// 统计某个文件夹整棵子树里 2MB 以上文件的扩展名分布;small = 被合并的小文件/小文件夹的总大小
    static func compute(_ cur: Node) -> (stats: [ExtStat], small: Int64) {
        var dict: [String: ExtStat] = [:]
        var small: Int64 = 0
        func walk(_ n: Node, inApp: Bool) {
            for c in n.children {
                if c.isAggregate {
                    small += c.size
                } else if c.isDir {
                    walk(c, inApp: inApp || c.url.pathExtension.lowercased() == "app")
                } else {
                    let k = extKey(c.url)
                    var s = dict[k] ?? ExtStat(ext: k, bytes: 0, count: 0,
                                               category: Category.of(c.url, inApp: inApp))
                    s.bytes += c.size
                    s.count += 1
                    dict[k] = s
                }
            }
        }
        walk(cur, inApp: cur.isInsideApp)
        return (dict.values.sorted { $0.bytes > $1.bytes }, small)
    }
}

extension ViewModel {
    func refreshExtStats() {
        guard viewMode == .types, typeGrouping == .byExtension, let cur = current else {
            extStats = []
            extSmallBytes = 0
            refreshExtHighlight()
            return
        }
        let r = ExtStats.stats(for: cur, root: root)
        extStats = r.stats
        extSmallBytes = r.small
        extExact = r.exact
        refreshExtHighlight()
    }

    /// 算出环形图里每个节点包含多少所选扩展名的文件,用来高亮它的分布
    func refreshExtHighlight() {
        guard viewMode == .types, typeGrouping == .byExtension,
              let e = selectedExt, let cur = current else {
            extHighlight = [:]
            return
        }
        var d: [UUID: Int64] = [:]
        @discardableResult
        func walk(_ n: Node) -> Int64 {
            if n.isAggregate { return 0 }
            if !n.isDir {
                let b: Int64 = extKey(n.url) == e ? n.size : 0
                d[n.id] = b
                return b
            }
            var sum: Int64 = 0
            for c in n.children { sum += walk(c) }
            d[n.id] = sum
            return sum
        }
        walk(cur)
        extHighlight = d
        extHighlightColor = extStats.first { $0.ext == e }?.category.color ?? appAccent
    }
}

extension SunburstLayout {
    /// 选中某个扩展名时的扇形颜色:包含的该扩展名文件越多越鲜艳,没有的变灰变淡
    static func extColor(_ s: Segment, hovered: Bool, bytes: Int64, color: Color) -> Color {
        if s.node.isAggregate { return Color(white: 0.5).opacity(0.12) }
        if bytes <= 0 { return Color(white: 0.5).opacity(hovered ? 0.35 : 0.16) }
        let share = Double(bytes) / Double(max(s.node.size, 1))
        return color.opacity(min(1.0, 0.4 + 0.6 * share + (hovered ? 0.15 : 0)))
    }
}

/// 环形图下方的提示条:正在高亮哪个扩展名,点 ✕ 取消
struct ExtHighlightChip: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        if let e = vm.selectedExt {
            let stat = vm.extStats.first { $0.ext == e }
            HStack(spacing: 6) {
                Circle().fill(vm.extHighlightColor).frame(width: 8, height: 8)
                Text(tr("高亮 \(extLabel(e))", "Highlighting \(extLabel(e))"))
                    .font(.caption)
                if let s = stat {
                    Text("· " + tr("\(s.count) 个文件 · \(formatSize(s.bytes))",
                                   "\(s.count) file\(s.count == 1 ? "" : "s") · \(formatSize(s.bytes))"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    vm.selectedExt = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(tr("取消高亮", "Clear highlight"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
            .help(tr("图上只高亮 2MB 以上的文件", "The chart only highlights files of 2 MB or more"))
        }
    }
}

struct ExtensionListView: View {
    @ObservedObject var vm: ViewModel
    let node: Node
    @State private var query = ""

    private var shown: [ExtStat] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ".", with: "")
        if q.isEmpty { return vm.extStats }
        return vm.extStats.filter { $0.ext.contains(q) }
    }

    var body: some View {
        let total = max(node.size, 1)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("筛选扩展名,例如 mp4", "Filter extensions, e.g. mp4"), text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()

            if vm.extStats.isEmpty {
                Text(tr("这里没有 2MB 以上的文件", "No files of 2 MB or more here"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown.prefix(300)) { s in
                            row(s, total: total)
                        }
                        if query.isEmpty && vm.extSmallBytes > 0 {
                            smallRow(total: total)
                        }
                    }
                }
                Text(vm.extExact
                     ? tr("这是整个扫描范围的精确统计,包含所有小文件。点进去只列出 2MB 以上的文件。扩展名不区分大小写。",
                          "Exact totals for the whole scan, including every small file. Opening one lists only files of 2 MB or more. Extensions are case-insensitive.")
                     : tr("子文件夹里只有 2MB 以上的文件能按扩展名统计,更小的文件合并成一行。回到扫描根目录可看到包含所有小文件的精确统计。",
                          "Inside a subfolder only files of 2 MB or more are counted per extension; smaller ones are merged into one row. Go back to the scan root for exact totals including every small file."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
    }

    private func row(_ s: ExtStat, total: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.category.icon)
                .foregroundStyle(s.category.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.label).lineLimit(1)
                    Text(tr("\(s.count) 个文件", "\(s.count) file\(s.count == 1 ? "" : "s")"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(s.category.color)
                            .frame(width: g.size.width * CGFloat(Double(s.bytes) / Double(total)))
                    }
                }
                .frame(height: 4)
            }
            Text(String(format: "%.1f%%", Double(s.bytes) / Double(total) * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            Text(formatSize(s.bytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { vm.selectedExt = s.ext }
    }

    private func smallRow(total: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("小文件(每项不足 2MB)", "Small items (under 2 MB each)")).lineLimit(1)
                Text(tr("没法再按扩展名拆分", "Can't be split by extension"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1f%%", Double(vm.extSmallBytes) / Double(total) * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            Text(formatSize(vm.extSmallBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            Color.clear.frame(width: 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
