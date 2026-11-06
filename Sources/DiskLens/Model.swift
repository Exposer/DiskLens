import SwiftUI
import AppKit

func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - 数据模型

final class Node: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let isDir: Bool
    var isAggregate = false          // “小文件”合并节点
    var size: Int64
    var children: [Node] = []
    weak var parent: Node?
    /// 目录节点:整棵子树按文件类型汇总的字节数(下标 = Category.rawValue)。文件节点为空。
    var cats: [Int64] = []
    /// 文件的最后修改时间(只记录文件,目录为 nil)
    var mod: Date?

    init(url: URL, name: String? = nil, isDir: Bool, size: Int64 = 0) {
        self.url = url
        self.name = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.isDir = isDir
        self.size = size
    }
}

// MARK: - 扫描器

final class DiskScanner: @unchecked Sendable {
    private struct Entry { let url: URL; let isDir: Bool; let size: Int64; let mod: Date? }

    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var cancelled = false
    /// 小于该阈值的文件/目录会被合并成一个“小文件”节点,节省内存
    private let threshold: Int64 = 2 * 1024 * 1024

    private static let skipPaths: Set<String> = [
        "/Volumes", "/System/Volumes", "/dev", "/cores", "/private/var/vm"
    ]
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentModificationDateKey
    ]

    private var path = ""
    var scannedBytes: Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
    /// 当前正在扫描的目录(用于扫描动画下方的实时显示)
    var currentPath: String { lock.lock(); defer { lock.unlock() }; return path }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    /// 扫描是否被中途取消(此时得到的树是不完整的)
    var wasCancelled: Bool { isCancelled }
    private func add(_ n: Int64) { lock.lock(); bytes += n; lock.unlock() }

    func scan(_ url: URL) -> Node {
        let root = Node(url: url, isDir: true)
        let entries = list(url)
        var results = [Node?](repeating: nil, count: entries.count)
        let resultLock = NSLock()

        // 第一层并行扫描,充分利用 M4 的多核
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let e = entries[i]
            let n = self.build(e.url, isDir: e.isDir, size: e.size, mod: e.mod, inApp: false)
            resultLock.lock(); results[i] = n; resultLock.unlock()
        }
        let top = results.compactMap { $0 }
        var cats = [Int64](repeating: 0, count: Category.count)
        for n in top {
            let t = n.categoryTotals(inApp: false)
            for i in 0..<Category.count { cats[i] += t[i] }
        }
        root.cats = cats
        finish(root, kids: top)
        return root
    }

    private func finish(_ node: Node, kids: [Node]) {
        var total: Int64 = 0
        var small: Int64 = 0
        var kept: [Node] = []
        for k in kids {
            total += k.size
            if k.size >= threshold { k.parent = node; kept.append(k) } else { small += k.size }
        }
        if small > 0 {
            let agg = Node(url: node.url, name: "小文件 / Small items", isDir: false, size: small)
            agg.isAggregate = true
            agg.parent = node
            kept.append(agg)
        }
        node.size = total
        node.children = kept.sorted { $0.size > $1.size }
    }

    private func build(_ url: URL, isDir: Bool, size: Int64, mod: Date? = nil, inApp: Bool) -> Node {
        let node = Node(url: url, isDir: isDir, size: size)
        node.mod = isDir ? nil : mod
        if !isDir { add(size); return node }
        if isCancelled { return node }
        lock.lock(); path = url.path; lock.unlock()

        // .app 包里的所有文件都算“应用程序”
        let inApp = inApp || url.pathExtension.lowercased() == "app"
        var cats = [Int64](repeating: 0, count: Category.count)
        var kids: [Node] = []
        var fileBytes: Int64 = 0
        for e in list(url) {
            if isCancelled { break }
            if e.isDir {
                let c = build(e.url, isDir: true, size: 0, inApp: inApp)
                if c.cats.count == Category.count {
                    for i in 0..<Category.count { cats[i] += c.cats[i] }
                }
                kids.append(c)
            } else {
                fileBytes += e.size
                cats[Category.of(e.url, inApp: inApp).rawValue] += e.size
                let fileNode = Node(url: e.url, isDir: false, size: e.size)
                fileNode.mod = e.mod
                kids.append(fileNode)
            }
        }
        add(fileBytes)
        node.cats = cats
        finish(node, kids: kids)
        return node
    }

    private func list(_ url: URL) -> [Entry] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Self.keys, options: []) else { return [] }
        var out: [Entry] = []
        out.reserveCapacity(items.count)
        for u in items {
            if Self.skipPaths.contains(u.path) { continue }
            let v = try? u.resourceValues(forKeys: Set(Self.keys))
            if v?.isSymbolicLink == true { continue }
            let size = Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
            out.append(Entry(url: u, isDir: v?.isDirectory == true, size: size,
                             mod: v?.contentModificationDate))
        }
        return out
    }
}

// MARK: - 环形图布局

struct Segment {
    let node: Node
    let level: Int       // 1 = 最内圈
    let a0: Double       // 弧度,0 在正上方,顺时针
    var a1: Double
    let hue: Double
    let cats: [Int64]    // 该节点按文件类型的字节数(用于“按类型着色”)
    let dominant: Category
}

enum SunburstLayout {
    static let maxLevel = 4

    static func segments(for root: Node) -> [Segment] {
        var out: [Segment] = []
        func walk(_ n: Node, _ level: Int, _ a0: Double, _ a1: Double, _ hue: Double?, _ inApp: Bool) {
            guard level <= maxLevel, n.size > 0 else { return }
            var a = a0
            for (i, c) in n.children.enumerated() {
                let span = (a1 - a0) * Double(c.size) / Double(n.size)
                defer { a += span }
                if span < 0.01 { continue }          // 太窄的扇形不画
                let h = hue ?? fmod(0.58 + Double(i) * 0.137, 1.0)
                let totals = c.categoryTotals(inApp: inApp)
                var best = Category.other
                var bestBytes: Int64 = 0
                for cat in Category.allCases where totals[cat.rawValue] > bestBytes {
                    best = cat; bestBytes = totals[cat.rawValue]
                }
                out.append(Segment(node: c, level: level, a0: a, a1: a + span, hue: h,
                                   cats: totals, dominant: best))
                let childInApp = inApp || (c.isDir && c.url.pathExtension.lowercased() == "app")
                walk(c, level + 1, a, a + span, h, childInApp)
            }
        }
        walk(root, 1, 0, 2 * .pi, nil, root.isInsideApp)
        return out
    }

    static func color(_ s: Segment, hovered: Bool) -> Color {
        if s.node.isAggregate { return Color(white: hovered ? 0.72 : 0.55) }
        let sat = max(0.25, 0.62 - 0.1 * Double(s.level - 1))
        let bri = min(1.0, 0.82 + 0.04 * Double(s.level - 1) + (hovered ? 0.12 : 0))
        return tc(s.hue, sat, bri)
    }
}

struct RingGeometry {
    let center: CGPoint
    let r0: CGFloat      // 中心空洞半径
    let w: CGFloat       // 每圈宽度

    init(size: CGSize) {
        let R = max(10, min(size.width, size.height) / 2 - 6)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        r0 = R * 0.24
        w = (R - r0) / CGFloat(SunburstLayout.maxLevel)
    }

    private func point(_ r: CGFloat, _ a: Double) -> CGPoint {
        CGPoint(x: center.x + r * CGFloat(sin(a)), y: center.y - r * CGFloat(cos(a)))
    }

    func path(for s: Segment) -> Path {
        let ri = r0 + CGFloat(s.level - 1) * w + 1
        let ro = r0 + CGFloat(s.level) * w - 1
        let n = max(2, Int((s.a1 - s.a0) / 0.03) + 1)
        var p = Path()
        p.move(to: point(ro, s.a0))
        for i in 1...n { p.addLine(to: point(ro, s.a0 + (s.a1 - s.a0) * Double(i) / Double(n))) }
        for i in stride(from: n, through: 0, by: -1) {
            p.addLine(to: point(ri, s.a0 + (s.a1 - s.a0) * Double(i) / Double(n)))
        }
        p.closeSubpath()
        return p
    }

    enum Hit { case center, outside, ring(level: Int, angle: Double) }

    func hit(_ pt: CGPoint) -> Hit {
        let dx = Double(pt.x - center.x), dy = Double(pt.y - center.y)
        let r = CGFloat(hypot(dx, dy))
        if r < r0 { return .center }
        var a = atan2(dx, -dy)
        if a < 0 { a += 2 * .pi }
        let level = Int(ceil((r - r0) / w))
        if level < 1 || level > SunburstLayout.maxLevel { return .outside }
        return .ring(level: level, angle: a)
    }
}

// MARK: - ViewModel

@MainActor
final class ViewModel: ObservableObject {
    @Published var root: Node?
    @Published var current: Node? {
        didSet { rebuild(); startReveal(); refreshTopFiles(); refreshBigFiles(); refreshExtStats() }
    }
    @Published var viewMode: ViewMode = .folders {
        didSet {
            refreshTopFiles()
            refreshBigFiles()
            refreshExtStats()
            if viewMode == .hogs && hogs.isEmpty && !hogsLoading { refreshHogs() }
        }
    }
    @Published var selectedCategory: Category? { didSet { refreshTopFiles() } }
    @Published var typeGrouping: TypeGrouping = .category {
        didSet { refreshTopFiles(); refreshExtStats() }
    }
    @Published var selectedExt: String? { didSet { refreshTopFiles() } }   // "" = 没有扩展名
    @Published var extStats: [ExtStat] = []     // 按扩展名统计
    @Published var extSmallBytes: Int64 = 0     // 被合并的小文件总大小
    @Published var topFiles: [Node] = []        // “按类型”模式下,所选类型里最大的文件
    @Published var hogs: [HogItem] = []         // “占用大户”列表
    @Published var hogsLoading = false
    @Published var scanStopped = false          // 扫描被手动停止,当前结果不完整
    @Published var bigFiles: [BigFile] = []     // 大文件排行榜
    @Published var bigFilter: Category? { didSet { refreshBigFiles() } }
    @Published var bigLimit = 100 { didSet { refreshBigFiles() } }
    @Published var bigMinAgeMonths = 0 { didSet { refreshBigFiles() } }   // 0 = 不限修改时间
    @Published var bigSort: BigSort = .size { didSet { refreshBigFiles() } }
    @Published var dupGroups: [DupGroup] = []   // 重复文件查找结果
    @Published var dupState: DupState = .idle
    @Published var dupStatus = ""
    @Published var dupMinSizeMB = 1
    @Published var dupStopped = false
    var dupScope: URL?
    var dupJob: DupJob?
    var dupTimer: Timer?
    @Published var hovered: Node?
    @Published var scanning = false
    @Published var scannedBytes: Int64 = 0
    @Published var target: URL = {
        if let p = UserDefaults.standard.string(forKey: "lastTarget"),
           FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    @Published var scanDate: Date?              // 当前显示的结果是什么时候扫描的
    @Published var isCached = false             // true = 来自上次保存的结果,不是刚扫描的
    @Published var pendingTrash: Node?
    @Published var errorMessage: String?
    @Published var scanningPath = ""
    @Published var revealing = false            // 环形图“展开”动画进行中
    @Published var collected: [Node] = []       // 收集器里的项目
    @Published var confirmTrashCollected = false
    @Published var dragNode: Node?              // 正从环形图拖出的节点
    @Published var dragPoint: CGPoint?          // 拖动位置(root 坐标系)
    var dragging: Node?                         // 正从列表拖出的节点
    var collectorFrame: CGRect = .zero
    var revealStart = Date()
    private var revealToken = 0

    private(set) var segments: [Segment] = []
    private var scanner: DiskScanner?
    private var timer: Timer?

    private func rebuild() {
        segments = current.map { SunburstLayout.segments(for: $0) } ?? []
    }

    var trail: [Node] {
        var out: [Node] = []
        var n = current
        while let x = n { out.insert(x, at: 0); n = x.parent }
        return out
    }

    func scan(_ url: URL) {
        scanner?.cancel()
        timer?.invalidate()
        let s = DiskScanner()
        scanner = s
        target = url
        root = nil; current = nil; hovered = nil
        collected = []; scanningPath = ""; selectedCategory = nil; selectedExt = nil
        isCached = false; scanDate = nil; scanStopped = false
        UserDefaults.standard.set(url.path, forKey: "lastTarget")
        scanning = true
        scannedBytes = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak s] _ in
            guard let s else { return }
            let v = s.scannedBytes
            let p = s.currentPath
            Task { @MainActor in
                self?.scannedBytes = v
                self?.scanningPath = p
            }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let r = s.scan(url)
            let date = Date()
            // 先在后台生成可序列化的快照,界面更新后再写盘
            let snap = ScanSnapshot(path: url.path, date: date, root: ScanStore.dto(r))
            let accepted = await MainActor.run { () -> Bool in
                guard let self, self.scanner === s else { return false }
                self.timer?.invalidate()
                self.root = r
                self.current = r
                self.scanDate = date
                self.isCached = false
                self.scanStopped = s.wasCancelled
                self.scanning = false
                return true
            }
            // 被取消的扫描结果不完整,不保存
            if accepted && !s.wasCancelled { try? ScanStore.write(snap) }
        }
    }

    /// 启动时调用:有上次保存的结果就直接载入,没有再扫描
    func loadCachedOrScan() {
        guard root == nil, !scanning, scanner == nil else { return }
        let url = target
        scanning = true
        scanningPath = tr("正在读取上次保存的扫描结果…", "Loading the last saved scan…")
        Task.detached(priority: .userInitiated) { [weak self] in
            let loaded = ScanStore.load(path: url.path)
            await MainActor.run {
                guard let self, self.root == nil, self.scanner == nil else { return }
                self.scanning = false
                if let loaded {
                    self.root = loaded.root
                    self.current = loaded.root
                    self.scanDate = loaded.date
                    self.isCached = true
                } else {
                    self.scan(url)
                }
            }
        }
    }

    /// 停止当前扫描:已扫到的部分会保留并显示,但标记为不完整,也不会保存为缓存
    func stopScan() {
        guard scanning, let s = scanner else { return }
        s.cancel()
        scanStopped = true
    }

    /// 清理(移到废纸篓)之后,把更新后的结果重新存盘,日期保持为原扫描时间
    private func saveCache() {
        guard let r = root, !scanning, !scanStopped else { return }
        let snap = ScanSnapshot(path: r.url.path, date: scanDate ?? Date(), root: ScanStore.dto(r))
        Task.detached(priority: .utility) { try? ScanStore.write(snap) }
    }

    func open(_ n: Node) {
        if n.isDir && !n.children.isEmpty { current = n }
    }

    func goUp() {
        if let p = current?.parent { current = p }
    }

    func reveal(_ n: Node) {
        NSWorkspace.shared.activateFileViewerSelecting([n.url])
    }

    func trash(_ n: Node) { trashItems([n]) }

    func trashItems(_ nodes: [Node]) {
        var failures: [String] = []
        for n in nodes {
            do {
                try FileManager.default.trashItem(at: n.url, resultingItemURL: nil)
                // 占用大户这类独立节点不在扫描树里:按路径找到树里对应的节点再摘除
                if let target = n.parent == nil ? findInTree(n.url) : n { detach(target) }
                collected.removeAll { urlIsInside($0.url, of: n.url) }
            } catch {
                failures.append("\(n.name): \(error.localizedDescription)")
            }
        }
        hovered = nil
        rebuild()
        refreshTopFiles()
        saveCache()
        if !hogs.isEmpty { refreshHogs() }
        if !dupGroups.isEmpty { pruneDuplicates() }
        refreshBigFiles()
        refreshExtStats()
        objectWillChange.send()
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    // MARK: 按文件类型

    /// 当前目录下、所选类型里最大的文件(仅统计已保留的 ≥2MB 的文件)
    func refreshTopFiles() {
        guard viewMode == .types, let cur = current else {
            topFiles = []
            return
        }
        // 按类别:选中的类别;按扩展名:选中的扩展名
        let cat: Category? = typeGrouping == .category ? selectedCategory : nil
        let ext: String? = typeGrouping == .byExtension ? selectedExt : nil
        guard cat != nil || ext != nil else {
            topFiles = []
            return
        }
        var out: [Node] = []
        func walk(_ n: Node, inApp: Bool) {
            for c in n.children where !c.isAggregate {
                if c.isDir {
                    walk(c, inApp: inApp || c.url.pathExtension.lowercased() == "app")
                } else if let cat {
                    if Category.of(c.url, inApp: inApp) == cat { out.append(c) }
                } else if let ext {
                    if extKey(c.url) == ext { out.append(c) }
                }
            }
        }
        walk(cur, inApp: cur.isInsideApp)
        topFiles = Array(out.sorted { $0.size > $1.size }.prefix(200))
    }

    // MARK: 展开动画

    private func startReveal() {
        revealStart = Date()
        revealing = true
        revealToken += 1
        let token = revealToken
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if token == revealToken { revealing = false }
        }
    }

    // MARK: 收集器

    var collectedSize: Int64 { collected.reduce(0) { $0 + $1.size } }

    /// 它自己,或它的某个上级目录,已经在收集器里
    func isCollected(_ n: Node) -> Bool {
        collected.contains { urlIsInside(n.url, of: $0.url) }
    }

    func collect(_ n: Node) {
        guard !n.isAggregate else { return }
        // 已收集了它的上级目录(或它本身):不重复计算
        if isCollected(n) { return }
        // 收集了上级目录:把已收集的子项合并掉
        collected.removeAll { urlIsInside($0.url, of: n.url) }
        collected.append(n)
    }

    // MARK: 从扫描树里摘除节点

    private func detach(_ n: Node) {
        let s = n.size
        let t = n.categoryTotals(inApp: n.parent?.isInsideApp ?? false)
        var p = n.parent
        n.parent?.children.removeAll { $0 === n }
        while let q = p {
            q.size -= s
            if q.cats.count == Category.count {
                for i in 0..<Category.count { q.cats[i] = max(0, q.cats[i] - t[i]) }
            }
            p = q.parent
        }
    }

    private func findInTree(_ url: URL) -> Node? {
        guard let r = root else { return nil }
        let rp = r.url.standardizedFileURL.pathComponents
        let up = url.standardizedFileURL.pathComponents
        guard up.count > rp.count, Array(up.prefix(rp.count)) == rp else { return nil }
        var cur = r
        for comp in up[rp.count...] {
            guard let next = cur.children.first(where: { !$0.isAggregate && $0.name == comp }) else { return nil }
            cur = next
        }
        return cur
    }

    func uncollect(_ n: Node) { collected.removeAll { $0 === n } }
    func clearCollector() { collected = [] }
}
