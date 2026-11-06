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

enum ExtStats {
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
            return
        }
        let r = ExtStats.compute(cur)
        extStats = r.stats
        extSmallBytes = r.small
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
                Text(tr("2MB 以上的文件按扩展名精确统计;更小的文件在扫描时已合并,只显示总大小。扩展名不区分大小写。",
                        "Files of 2 MB or more are counted per extension; smaller ones were merged during the scan and only their total size is shown. Extensions are case-insensitive."))
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
