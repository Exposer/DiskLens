import SwiftUI

enum ViewMode: CaseIterable, Hashable {
    case folders, types, hogs

    var title: String {
        switch self {
        case .folders: return tr("文件夹", "Folders")
        case .types: return tr("文件类型", "File Types")
        case .hogs: return tr("占用大户", "Space Hogs")
        }
    }
}

/// 文件类型分类(按扩展名;.app 包内的所有文件算“应用程序”)
enum Category: Int, CaseIterable, Identifiable {
    case video, audio, image, document, archive, app, code, other

    var id: Int { rawValue }
    static var count: Int { allCases.count }

    var title: String {
        switch self {
        case .video: return tr("视频", "Video")
        case .audio: return tr("音频", "Audio")
        case .image: return tr("图片", "Images")
        case .document: return tr("文档", "Documents")
        case .archive: return tr("压缩包 / 安装包 / 磁盘映像", "Archives / Installers / Disk Images")
        case .app: return tr("应用程序", "Apps")
        case .code: return tr("代码 / 开发文件", "Code / Dev Files")
        case .other: return tr("其他", "Other")
        }
    }

    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .image: return "photo"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .app: return "app.dashed"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "questionmark.folder"
        }
    }

    var color: Color {
        switch self {
        case .video: return tc(0.98, 0.6, 0.92)
        case .audio: return tc(0.80, 0.5, 0.9)
        case .image: return tc(0.38, 0.55, 0.8)
        case .document: return tc(0.58, 0.6, 0.9)
        case .archive: return tc(0.10, 0.7, 0.95)
        case .app: return tc(0.68, 0.55, 0.9)
        case .code: return tc(0.47, 0.55, 0.8)
        case .other: return Color(white: 0.55)
        }
    }

    private static let table: [String: Category] = {
        var t: [String: Category] = [:]
        func add(_ c: Category, _ exts: String) {
            for e in exts.split(separator: " ") { t[String(e)] = c }
        }
        add(.video, "mp4 mov m4v mkv avi wmv flv webm mpg mpeg mts m2ts mxf prproj fcpbundle")
        add(.audio, "mp3 m4a aac wav aiff aif flac ogg opus wma caf band logicx")
        add(.image, "jpg jpeg png gif heic heif tiff tif bmp webp raw cr2 cr3 nef arw dng psd ai sketch svg icns photoslibrary")
        add(.document, "pdf doc docx xls xlsx ppt pptx pages numbers key txt rtf md csv epub mobi odt ods odp")
        add(.archive, "zip rar 7z tar gz tgz bz2 xz zst dmg pkg iso img sparseimage sparsebundle vmdk vdi qcow2 vhd ipa xip")
        add(.app, "app")
        add(.code, "swift m mm h c cc cpp hpp rs go py pyc js mjs cjs ts tsx jsx java class jar kt rb php cs sh json yaml yml toml xml html css scss map o a dylib so lib obj d pdb dsym ipynb sql db sqlite")
        return t
    }()

    static func of(_ url: URL, inApp: Bool) -> Category {
        if inApp { return .app }
        return table[url.pathExtension.lowercased()] ?? .other
    }
}

extension Node {
    /// 这个节点(子树)按类型汇总的字节数。文件节点返回单一类型。
    func categoryTotals(inApp: Bool) -> [Int64] {
        var t = [Int64](repeating: 0, count: Category.count)
        if isDir {
            return cats.count == Category.count ? cats : t
        }
        if isAggregate { return t }
        t[Category.of(url, inApp: inApp).rawValue] = size
        return t
    }

    /// 自己或某个上级是 .app 包
    var isInsideApp: Bool {
        var n: Node? = self
        while let x = n {
            if x.url.pathExtension.lowercased() == "app" && !x.isAggregate { return true }
            n = x.parent
        }
        return false
    }
}

// MARK: - 环形图按类型着色

extension SunburstLayout {
    /// “文件类型”模式下的扇形颜色:
    /// - 未选类型:按该节点里占比最大的类型着色
    /// - 选了某一类型:该类型占比越高越鲜艳,没有该类型的扇形变灰变淡
    static func typeColor(_ s: Segment, hovered: Bool, selected: Category?) -> Color {
        if s.node.isAggregate { return Color(white: hovered ? 0.72 : 0.55).opacity(selected == nil ? 1 : 0.2) }
        if let sel = selected {
            let share = Double(s.cats[sel.rawValue]) / Double(max(s.node.size, 1))
            if share <= 0.001 { return Color(white: 0.5).opacity(hovered ? 0.35 : 0.16) }
            return sel.color.opacity(min(1.0, 0.3 + 0.7 * share + (hovered ? 0.15 : 0)))
        }
        let fade = max(0.6, 0.98 - 0.1 * Double(s.level - 1))
        return s.dominant.color.opacity(hovered ? 1.0 : fade)
    }
}

/// 环形图下方的图例:点击某类型 = 高亮该类型在哪里,再点一次取消
struct TypeLegend: View {
    @ObservedObject var vm: ViewModel
    let node: Node

    var body: some View {
        let totals = node.categoryTotals(inApp: node.isInsideApp)
        let items = Category.allCases
            .filter { totals[$0.rawValue] > 0 }
            .sorted { totals[$0.rawValue] > totals[$1.rawValue] }
        HStack(spacing: 6) {
            ForEach(items) { cat in
                let on = vm.selectedCategory == cat
                Button {
                    vm.selectedCategory = on ? nil : cat
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(cat.color).frame(width: 8, height: 8)
                        Text(cat.title.components(separatedBy: " ").first ?? cat.title)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(on ? cat.color.opacity(0.25) : Color.clear))
                    .overlay(Capsule().strokeBorder(on ? cat.color : Color.secondary.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("\(cat.title) · \(formatSize(totals[cat.rawValue]))")
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - 类型汇总视图

struct CategoryListView: View {
    @ObservedObject var vm: ViewModel
    let node: Node

    var body: some View {
        let totals = node.categoryTotals(inApp: node.isInsideApp)
        let sum = max(totals.reduce(0, +), 1)
        let sorted = Category.allCases.sorted { totals[$0.rawValue] > totals[$1.rawValue] }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 堆叠总览条
                GeometryReader { g in
                    HStack(spacing: 1) {
                        ForEach(sorted) { cat in
                            let frac = Double(totals[cat.rawValue]) / Double(sum)
                            if frac > 0 {
                                Rectangle().fill(cat.color)
                                    .frame(width: max(1, g.size.width * CGFloat(frac)))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 14)
                .padding(12)

                ForEach(sorted) { cat in
                    row(cat, bytes: totals[cat.rawValue], sum: sum)
                }

                Text(tr("统计的是当前文件夹整棵子树里的全部文件。点一个类型,可以查看该类型里最大的文件。",
                        "Totals cover every file in the current folder's whole subtree. Click a type to see its largest files."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }

    private func row(_ cat: Category, bytes: Int64, sum: Int64) -> some View {
        let frac = Double(bytes) / Double(sum)
        return HStack(spacing: 10) {
            Image(systemName: cat.icon)
                .foregroundStyle(cat.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(cat.title).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(cat.color)
                            .frame(width: g.size.width * CGFloat(frac))
                    }
                }
                .frame(height: 4)
            }
            Text(String(format: "%.1f%%", frac * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            Text(formatSize(bytes))
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
        .onTapGesture { if bytes > 0 { vm.selectedCategory = cat } }
    }
}
