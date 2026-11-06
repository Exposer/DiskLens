import SwiftUI
import AppKit
import UniformTypeIdentifiers

// 导出扫描报告:Markdown(可读的总览)和 CSV(文件清单,Excel / Numbers 可直接打开)。
// 报告语言跟随界面语言;路径里的个人文件夹显示为 ~,避免把用户名带进分享出去的报告。

enum ReportKind { case markdown, csv }

extension ViewModel {
    func exportReport(_ kind: ReportKind) {
        guard let root, !scanning else { return }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let stamp = df.string(from: Date())

        let panel = NSSavePanel()
        switch kind {
        case .markdown:
            panel.title = tr("导出 Markdown 报告", "Export Markdown Report")
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "DiskLens-Report-\(stamp).md"
        case .csv:
            panel.title = tr("导出 CSV 文件清单", "Export CSV File List")
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "DiskLens-Files-\(stamp).csv"
        }
        panel.prompt = tr("导出", "Export")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch kind {
            case .markdown:
                try ReportBuilder.markdown(self, root: root).write(to: url, atomically: true, encoding: .utf8)
            case .csv:
                // 带 BOM,Excel 才能正确显示中文
                try ("\u{FEFF}" + ReportBuilder.csv(root: root)).write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ReportBuilder {
    // MARK: 公共工具

    private static func shortPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func pct(_ part: Int64, _ whole: Int64) -> String {
        String(format: "%.1f%%", Double(part) / Double(max(whole, 1)) * 100)
    }

    /// 一行 Markdown 表格
    private static func row(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    /// Markdown 表格里要转义竖线和换行
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    /// 扫描树里所有已保留的文件(≥2MB)及其类型
    private static func allFiles(_ root: Node) -> [(node: Node, cat: Category)] {
        var out: [(node: Node, cat: Category)] = []
        func walk(_ n: Node, inApp: Bool) {
            for c in n.children where !c.isAggregate {
                if c.isDir {
                    walk(c, inApp: inApp || c.url.pathExtension.lowercased() == "app")
                } else {
                    out.append((node: c, cat: Category.of(c.url, inApp: inApp)))
                }
            }
        }
        walk(root, inApp: root.isInsideApp)
        return out.sorted { $0.node.size > $1.node.size }
    }

    // MARK: Markdown

    @MainActor
    static func markdown(_ vm: ViewModel, root: Node) -> String {
        var md: [String] = []
        let total = max(root.size, 1)

        md.append("# " + tr("DiskLens 扫描报告", "DiskLens Scan Report"))
        md.append("")
        let lblPath = tr("扫描位置", "Scanned location")
        let lblScanned = tr("扫描时间", "Scanned at")
        let lblGenerated = tr("报告生成时间", "Report generated")
        let lblTotal = tr("已统计的文件总大小", "Total size of scanned files")
        md.append("- **\(lblPath)**: `\(shortPath(root.url))`")
        if let d = vm.scanDate {
            let note = vm.isCached ? tr("(来自保存的结果)", " (from saved results)") : ""
            md.append("- **\(lblScanned)**: \(formatDate(d))\(note)")
        }
        md.append("- **\(lblGenerated)**: \(formatDate(Date()))")
        md.append("- **\(lblTotal)**: \(formatSize(root.size))")
        if vm.scanStopped {
            md.append("- ⚠️ " + tr("扫描被手动停止,结果不完整,各文件夹的大小会偏小。",
                                  "The scan was stopped early. Results are incomplete and folder sizes are underestimated."))
        }
        md.append("")

        // 磁盘容量
        if let u = VolumeUsage.read() {
            md.append("## " + tr("磁盘容量", "Disk Capacity"))
            md.append("")
            md.append(row([tr("项目", "Item"), tr("大小", "Size"), tr("占比", "Share")]))
            md.append("|---|---:|---:|")
            md.append("| " + tr("容量", "Capacity") + " | \(formatSize(u.total)) | 100% |")
            md.append("| " + tr("已用", "Used") + " | \(formatSize(u.used)) | \(pct(u.used, u.total)) |")
            md.append("| " + tr("可清除", "Purgeable") + " | \(formatSize(u.purgeable)) | \(pct(u.purgeable, u.total)) |")
            md.append("| " + tr("空闲", "Free") + " | \(formatSize(u.free)) | \(pct(u.free, u.total)) |")
            md.append("")
            md.append("> " + tr("可清除空间是 macOS 在磁盘不足时会自动释放的内容,扫描看不到它们,所以扫描总和可能小于「已用」。",
                                "Purgeable space is reclaimed by macOS automatically when the disk runs low. A file scan can't see it, so the scanned total may be smaller than \"Used\"."))
            md.append("")
        }

        // 按文件类型
        let totals = root.categoryTotals(inApp: root.isInsideApp)
        let typeSum = max(totals.reduce(0, +), 1)
        md.append("## " + tr("按文件类型", "By File Type"))
        md.append("")
        md.append(row([tr("类型", "Type"), tr("大小", "Size"), tr("占比", "Share")]))
        md.append("|---|---:|---:|")
        for cat in Category.allCases.sorted(by: { totals[$0.rawValue] > totals[$1.rawValue] }) where totals[cat.rawValue] > 0 {
            md.append("| \(esc(cat.title)) | \(formatSize(totals[cat.rawValue])) | \(pct(totals[cat.rawValue], typeSum)) |")
        }
        md.append("")

        // 按扩展名(前 20)
        let ext = ExtStats.compute(root)
        if !ext.stats.isEmpty {
            md.append("## " + tr("按扩展名(前 20)", "By Extension (top 20)"))
            md.append("")
            md.append(row([tr("扩展名", "Extension"), tr("文件数", "Files"), tr("大小", "Size"), tr("占比", "Share")]))
            md.append("|---|---:|---:|---:|")
            for s in ext.stats.prefix(20) {
                md.append("| \(esc(s.label)) | \(s.count) | \(formatSize(s.bytes)) | \(pct(s.bytes, total)) |")
            }
            if ext.small > 0 {
                md.append("| \(tr("小文件(每项不足 2 MB)", "Small items (under 2 MB each)")) | - | \(formatSize(ext.small)) | \(pct(ext.small, total)) |")
            }
            md.append("")
        }

        // 最大的一级目录
        let top = root.children.filter { !$0.isAggregate }.prefix(20)
        if !top.isEmpty {
            md.append("## " + tr("最大的文件夹和文件(第一层)", "Largest Folders and Files (top level)"))
            md.append("")
            md.append(row([tr("名称", "Name"), tr("大小", "Size"), tr("占比", "Share")]))
            md.append("|---|---:|---:|")
            for n in top {
                md.append("| \(n.isDir ? "📁" : "📄") \(esc(n.name)) | \(formatSize(n.size)) | \(pct(n.size, total)) |")
            }
            md.append("")
        }

        // 最大的 50 个文件
        let files = Array(allFiles(root).prefix(50))
        if !files.isEmpty {
            md.append("## " + tr("最大的 50 个文件", "50 Largest Files"))
            md.append("")
            md.append(row(["#", tr("文件", "File"), tr("大小", "Size"), tr("类型", "Type"),
                           tr("修改时间", "Modified"), tr("位置", "Location")]))
            md.append("|--:|---|---:|---|---|---|")
            for (i, f) in files.enumerated() {
                let mod = f.node.mod.map { formatDate($0) } ?? "-"
                let dir = shortPath(f.node.url.deletingLastPathComponent())
                md.append("| \(i + 1) | \(esc(f.node.name)) | \(formatSize(f.node.size)) | \(esc(f.cat.title)) | \(mod) | `\(esc(dir))` |")
            }
            md.append("")
            md.append("> " + tr("只统计 2 MB 以上的文件。", "Only files of 2 MB or more are listed."))
            md.append("")
        }

        // 占用大户(如果看过这一页)
        if !vm.hogs.isEmpty {
            md.append("## " + tr("常见占用大户", "Common Space Hogs"))
            md.append("")
            md.append(row([tr("项目", "Item"), tr("大小", "Size"), tr("建议", "Advice"), tr("清理命令", "Command")]))
            md.append("|---|---:|---|---|")
            for h in vm.hogs {
                let cmd = h.def.command.map { "`\($0)`" } ?? "-"
                md.append("| \(esc(h.title)) | \(formatSize(h.size)) | \(h.def.level.title) | \(cmd) |")
            }
            md.append("")
        }

        // 重复文件(如果查找过)
        if !vm.dupGroups.isEmpty {
            let wasted = vm.dupGroups.reduce(Int64(0)) { $0 + $1.wasted }
            md.append("## " + tr("重复文件", "Duplicate Files"))
            md.append("")
            md.append(tr("共 \(vm.dupGroups.count) 组,删到每组只剩一份可释放约 **\(formatSize(wasted))**。",
                         "\(vm.dupGroups.count) groups; keeping one copy of each frees about **\(formatSize(wasted))**."))
            md.append("")
            for g in vm.dupGroups.prefix(30) {
                md.append("- **\(esc(g.files.first?.url.lastPathComponent ?? ""))** × \(g.files.count) · "
                          + tr("每份 \(formatSize(g.size)),可释放 \(formatSize(g.wasted))",
                               "\(formatSize(g.size)) each, frees \(formatSize(g.wasted))"))
                for f in g.files {
                    md.append("  - `\(shortPath(f.url))`")
                }
            }
            if vm.dupGroups.count > 30 {
                md.append("- … " + tr("另有 \(vm.dupGroups.count - 30) 组", "and \(vm.dupGroups.count - 30) more groups"))
            }
            md.append("")
        }

        // 收集器
        if !vm.collected.isEmpty {
            md.append("## " + tr("收集器中的待清理项目", "Items Waiting in the Collector"))
            md.append("")
            md.append(row([tr("项目", "Item"), tr("大小", "Size"), tr("位置", "Location")]))
            md.append("|---|---:|---|")
            for n in vm.collected {
                md.append("| \(esc(n.displayName)) | \(formatSize(n.size)) | `\(esc(shortPath(n.url)))` |")
            }
            md.append("")
            md.append(tr("合计 **\(formatSize(vm.collectedSize))**。", "Total **\(formatSize(vm.collectedSize))**."))
            md.append("")
        }

        md.append("---")
        md.append("*" + tr("由 DiskLens 生成。路径中的个人文件夹显示为 ~。",
                           "Generated by DiskLens. Your home folder is shown as ~ in paths.") + "*")
        md.append("")
        return md.joined(separator: "\n")
    }

    // MARK: CSV

    private static func field(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 扫描结果里所有 ≥2MB 的文件,按大小从大到小
    static func csv(root: Node) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append([tr("路径", "path"), tr("名称", "name"), tr("大小(字节)", "size_bytes"),
                      tr("大小", "size"), tr("类型", "type"), tr("最后修改时间", "modified")]
            .map(field).joined(separator: ","))
        for f in allFiles(root) {
            let row: [String] = [
                shortPath(f.node.url),
                f.node.name,
                String(f.node.size),
                formatSize(f.node.size),
                f.cat.title,
                f.node.mod.map { iso.string(from: $0) } ?? ""
            ]
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - 工具栏菜单

struct ExportMenu: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        Menu {
            Button(tr("导出 Markdown 报告…", "Export Markdown Report…")) { vm.exportReport(.markdown) }
            Button(tr("导出 CSV 文件清单…", "Export CSV File List…")) { vm.exportReport(.csv) }
        } label: {
            Label(tr("导出", "Export"), systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(vm.root == nil || vm.scanning)
        .help(tr("把扫描结果导出成报告", "Export the scan results as a report"))
    }
}
