import Foundation

// 扫描结果的持久化:保存到 ~/Library/Application Support/DiskLens/,下次启动直接载入。

/// 可序列化的节点(用短键名减小文件体积)。URL 不保存,载入时由根路径 + 名称重建。
struct NodeDTO: Codable {
    var n: String          // 名称
    var d: Bool            // 是否目录
    var s: Int64           // 大小
    var c: [Int64]?        // 目录:按类型汇总
    var a: Bool?           // 是否“小文件”合并节点
    var k: [NodeDTO]?      // 子节点
    var m: Double?         // 文件的最后修改时间(自 1970 年起的秒数)
    var x: [String: ExtTotal]?   // 仅根节点:按扩展名的精确总表
}

struct ScanSnapshot: Codable {
    var version = 3        // 2:加入文件修改时间;3:加入按扩展名的精确总表。版本 2 的缓存仍可读取,只是没有精确总表
    var path: String       // 被扫描的根目录
    var date: Date
    var root: NodeDTO
}

enum ScanStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskLens", isDirectory: true)
    }

    /// 路径的 FNV-1a 哈希,用来给缓存文件命名
    private static func hashString(_ path: String) -> String {
        var h: UInt64 = 14695981039346656037
        for b in path.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return String(h, radix: 16)
    }

    /// 每个被扫描的目录一个“最新结果”缓存文件,文件名由路径的哈希决定
    static func fileURL(for path: String) -> URL {
        directory.appendingPathComponent("scan-\(hashString(path)).json")
    }

    // MARK: 历史快照(用于“对比扫描”)

    /// 每次完整扫描都会另存一份历史快照,每个目录保留最近 maxHistory 份
    static let maxHistory = 8

    static var historyDirectory: URL {
        directory.appendingPathComponent("history", isDirectory: true)
    }

    struct HistoryEntry: Identifiable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    private static func historyFile(_ path: String, date: Date) -> URL {
        historyDirectory.appendingPathComponent(
            "hist-\(hashString(path))-\(Int(date.timeIntervalSince1970)).json")
    }

    /// 某个目录的历史快照,最新的在前
    static func history(for path: String) -> [HistoryEntry] {
        let prefix = "hist-\(hashString(path))-"
        let files = (try? FileManager.default.contentsOfDirectory(
            at: historyDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { u -> HistoryEntry? in
            let name = u.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix), let t = TimeInterval(name.dropFirst(prefix.count)) else { return nil }
            return HistoryEntry(url: u, date: Date(timeIntervalSince1970: t))
        }
        .sorted { $0.date > $1.date }
    }

    /// 读取某个历史快照
    static func loadSnapshot(at url: URL) -> (root: Node, date: Date)? {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(ScanSnapshot.self, from: data),
              snap.version == 2 || snap.version == 3,
              snap.root.c?.count == Category.count else { return nil }
        return (node(from: snap.root, url: URL(fileURLWithPath: snap.path), parent: nil), snap.date)
    }

    // MARK: 节点 <-> DTO

    static func dto(_ n: Node) -> NodeDTO {
        NodeDTO(n: n.name,
                d: n.isDir,
                s: n.size,
                c: n.isDir && !n.cats.isEmpty ? n.cats : nil,
                a: n.isAggregate ? true : nil,
                k: n.children.isEmpty ? nil : n.children.map { dto($0) },
                m: n.mod?.timeIntervalSince1970,
                x: n.extTotals)
    }

    static func node(from dto: NodeDTO, url: URL, parent: Node?) -> Node {
        let n = Node(url: url, name: dto.n, isDir: dto.d, size: dto.s)
        n.isAggregate = dto.a == true
        n.cats = dto.c ?? []
        n.mod = dto.m.map { Date(timeIntervalSince1970: $0) }
        n.extTotals = dto.x
        n.parent = parent
        for k in dto.k ?? [] {
            let childURL = k.a == true ? url : url.appendingPathComponent(k.n, isDirectory: k.d)
            n.children.append(node(from: k, url: childURL, parent: n))
        }
        return n
    }

    // MARK: 读写

    /// 只更新“最新结果”(清理文件之后用;不产生新的历史快照)
    static func writeLatest(_ snap: ScanSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snap)
        try data.write(to: fileURL(for: snap.path), options: .atomic)
    }

    /// 一次完整扫描结束后:更新“最新结果”,并另存一份历史快照
    static func write(_ snap: ScanSnapshot) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: historyDirectory, withIntermediateDirectories: true)

        // 第一次保存历史前,把已有的“最新结果”也并入历史,这样马上就能和它对比
        let latest = fileURL(for: snap.path)
        if history(for: snap.path).isEmpty,
           let oldData = try? Data(contentsOf: latest),
           let old = try? JSONDecoder().decode(ScanSnapshot.self, from: oldData),
           old.path == snap.path, old.version >= 2 {
            try? oldData.write(to: historyFile(snap.path, date: old.date), options: .atomic)
        }

        let data = try JSONEncoder().encode(snap)
        try data.write(to: latest, options: .atomic)
        try data.write(to: historyFile(snap.path, date: snap.date), options: .atomic)

        for e in history(for: snap.path).dropFirst(maxHistory) {
            try? fm.removeItem(at: e.url)
        }
    }

    static func load(path: String) -> (root: Node, date: Date)? {
        guard let data = try? Data(contentsOf: fileURL(for: path)),
              let snap = try? JSONDecoder().decode(ScanSnapshot.self, from: data),
              snap.version == 2 || snap.version == 3,
              snap.path == path,
              // 文件类型数量变了(比如新版本增加了分类),旧缓存作废
              snap.root.c?.count == Category.count else { return nil }
        let root = node(from: snap.root, url: URL(fileURLWithPath: path), parent: nil)
        return (root, snap.date)
    }

    /// 已保存的扫描结果占用的磁盘空间
    static func totalSize() -> Int64 {
        let fm = FileManager.default
        var files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        files += (try? fm.contentsOfDirectory(at: historyDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { sum, u in
            sum + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
