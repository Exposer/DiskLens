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
}

struct ScanSnapshot: Codable {
    var version = 1
    var path: String       // 被扫描的根目录
    var date: Date
    var root: NodeDTO
}

enum ScanStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskLens", isDirectory: true)
    }

    /// 每个被扫描的目录一个缓存文件,文件名由路径的哈希决定
    static func fileURL(for path: String) -> URL {
        var h: UInt64 = 14695981039346656037
        for b in path.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return directory.appendingPathComponent("scan-\(String(h, radix: 16)).json")
    }

    // MARK: 节点 <-> DTO

    static func dto(_ n: Node) -> NodeDTO {
        NodeDTO(n: n.name,
                d: n.isDir,
                s: n.size,
                c: n.isDir && !n.cats.isEmpty ? n.cats : nil,
                a: n.isAggregate ? true : nil,
                k: n.children.isEmpty ? nil : n.children.map { dto($0) })
    }

    static func node(from dto: NodeDTO, url: URL, parent: Node?) -> Node {
        let n = Node(url: url, name: dto.n, isDir: dto.d, size: dto.s)
        n.isAggregate = dto.a == true
        n.cats = dto.c ?? []
        n.parent = parent
        for k in dto.k ?? [] {
            let childURL = k.a == true ? url : url.appendingPathComponent(k.n, isDirectory: k.d)
            n.children.append(node(from: k, url: childURL, parent: n))
        }
        return n
    }

    // MARK: 读写

    static func write(_ snap: ScanSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snap)
        try data.write(to: fileURL(for: snap.path), options: .atomic)
    }

    static func load(path: String) -> (root: Node, date: Date)? {
        guard let data = try? Data(contentsOf: fileURL(for: path)),
              let snap = try? JSONDecoder().decode(ScanSnapshot.self, from: data),
              snap.version == 1,
              snap.path == path,
              // 文件类型数量变了(比如新版本增加了分类),旧缓存作废
              snap.root.c?.count == Category.count else { return nil }
        let root = node(from: snap.root, url: URL(fileURLWithPath: path), parent: nil)
        return (root, snap.date)
    }

    /// 已保存的扫描结果占用的磁盘空间
    static func totalSize() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { sum, u in
            sum + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
