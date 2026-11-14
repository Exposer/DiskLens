import SwiftUI
import AppKit

func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - 数据模型

final class Node: Identifiable, @unchecked Sendable {
    /// 节点身份直接用对象地址,省掉每个节点一个 UUID
    var id: ObjectIdentifier { ObjectIdentifier(self) }
    /// 只有根节点和独立节点(占用大户、重复文件等)保存完整 URL;
    /// 扫描树里的其他节点只存名字,需要时由上级的 URL 拼出来,省下每个节点一份路径字符串。
    private var storedURL: URL?
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
    /// 仅扫描根目录:整个扫描范围内按扩展名的精确统计(包含所有小文件)
    var extTotals: [String: ExtTotal]?

    init(url: URL, name: String? = nil, isDir: Bool, size: Int64 = 0) {
        self.storedURL = url
        self.name = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.isDir = isDir
        self.size = size
    }

    /// 没有自己的 URL:路径由 parent 链推出(必须随后挂到某个上级下面)
    init(name: String, isDir: Bool, size: Int64 = 0) {
        self.storedURL = nil
        self.name = name
        self.isDir = isDir
        self.size = size
    }

    var url: URL {
        if let u = storedURL { return u }
        // 上级已经不在了(旧扫描树被换掉后还被别处拿着的节点):返回一个不可能存在的路径。
        // 以前这里返回的是相对路径 `name`,会被解析成“当前工作目录下的同名项目”,
        // 万一拿去移进废纸篓,动的就是一个不相干的文件。
        guard let p = parent else { return URL(fileURLWithPath: "/dev/null/detached/" + name) }
        return isAggregate ? p.url : p.url.appendingPathComponent(name, isDirectory: isDir)
    }

    /// 既没有自己的 URL、上级也已经释放:它的路径已经无从得知,不能再收集或删除
    var isOrphan: Bool { storedURL == nil && parent == nil }

    /// 已经挂到上级下面之后,丢掉自己保存的 URL(之后按需拼出)
    func releaseURL() { if parent != nil { storedURL = nil } }

    /// 小写扩展名,不用拼完整 URL
    var ext: String {
        if let u = storedURL { return u.pathExtension.lowercased() }
        return (name as NSString).pathExtension.lowercased()
    }

    var isAppBundle: Bool { ext == "app" }
}

// MARK: - 扫描器

final class DiskScanner: @unchecked Sendable {
    /// 一个文件(设备号 + 文件号)
    private struct FileKey: Hashable { let dev: UInt32; let id: UInt64 }

    /// 目录里的一个条目。URL 是按需生成的:绝大多数是小文件,根本用不到,省掉几十万次 URL 构造
    private struct Entry {
        let parent: URL
        let name: String
        let isDir: Bool
        let size: Int64
        let mod: Date?
        var url: URL { parent.appendingPathComponent(name, isDirectory: isDir) }
    }

    private let lock = NSLock()
    /// 已经算过大小的硬链接文件。只有链接数 > 1 的文件会进来,数量有限
    private let linkLock = NSLock()
    private var seenLinks = Set<FileKey>()
    /// 第一次遇到这个 inode 返回 true(要计入大小),之后的链接返回 false。
    /// 并行扫描时“第一个”是谁不固定,所以同一个 inode 的大小可能记在不同的名字下,总数不受影响
    private func countsLink(dev: UInt32, id: UInt64) -> Bool {
        linkLock.lock(); defer { linkLock.unlock() }
        return seenLinks.insert(FileKey(dev: dev, id: id)).inserted
    }
    private var bytes: Int64 = 0
    private var cancelled = false
    /// 小于该阈值的文件/目录会被合并成一个“小文件”节点,节省内存
    private let threshold: Int64 = 2 * 1024 * 1024

    private static let skipPaths: Set<String> = [
        "/Volumes", "/System/Volumes", "/dev", "/cores", "/private/var/vm",
        // 根目录下的路径解析入口:列出 /.nofollow 会得到整个根目录的第二份拷贝
        // (/.nofollow/Users、/.nofollow/System/Volumes/Data……),不跳过会把整块磁盘重复统计
        "/.nofollow", "/.resolve", "/.vol", "/.file"
    ]
    /// 云同步目录不算本地占用:iCloud 云盘 / App 容器(Mobile Documents)和各家云盘的文件提供程序目录(CloudStorage,
    /// 如 Dropbox、OneDrive、Google Drive)。里面没下载的文件本来就不占本地空间,而且遍历它们很慢。
    /// 只在它们作为子目录出现时跳过;如果你直接选它们作为扫描目标,仍然会扫。
    private static let cloudPaths: Set<String> = {
        let lib = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return [lib.appendingPathComponent("Mobile Documents").path,
                lib.appendingPathComponent("CloudStorage").path]
    }()
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentModificationDateKey, .volumeIdentifierKey
    ]
    private static let keySet = Set(keys)

    /// 不跨越文件系统边界(类似 `du -x`):挂载进目录树的磁盘映像(Xcode 模拟器运行时、系统资源镜像)、
    /// 外接盘、网络卷、自动挂载点都不会被算进去,否则同一份数据会被重复统计,总数甚至超过磁盘本身的容量。
    /// 从 "/" 扫描时,个人数据所在的 Data 卷(通过 firmlink 出现在 /Users、/Library 等位置)也允许进入。
    ///
    /// 批量读目录(getattrlistbulk)返回的是父目录文件系统里的条目,挂载点目录看起来仍然属于父卷,
    /// 所以不能再靠“条目所在卷”判断。改成扫描开始时用 getmntinfo 列出所有挂载点,
    /// 把不属于允许卷的挂载点路径收进拦截名单,遍历到时按路径跳过。
    private var blockedMounts: Set<String> = []

    private static func fsid(of path: String) -> [Int32]? {
        var st = statfs()
        guard statfs(path, &st) == 0 else { return nil }
        return [st.f_fsid.val.0, st.f_fsid.val.1]
    }

    private func computeBlockedMounts(root: URL) {
        blockedMounts = Self.blockedMountPaths(root: root)
    }

    /// 与扫描器共用的规则:重复文件查找等其他遍历也要按它跳过其它卷的挂载点
    static func blockedMountPaths(root: URL) -> Set<String> {
        var allowed: [[Int32]] = []
        if let r = Self.fsid(of: root.path) { allowed.append(r) }
        if root.standardizedFileURL.path == "/", let d = Self.fsid(of: "/System/Volumes/Data") { allowed.append(d) }
        var blocked: Set<String> = []
        var list: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&list, MNT_NOWAIT)
        if n > 0, let list {
            for i in 0..<Int(n) {
                var fs = list[i]
                let id = [fs.f_fsid.val.0, fs.f_fsid.val.1]
                if allowed.contains(id) { continue }
                let mp = withUnsafePointer(to: &fs.f_mntonname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
                blocked.insert(mp)
                // 从 "/" 扫描时同一个挂载点也可能以不带 Data 前缀的路径出现
                let dataPrefix = "/System/Volumes/Data"
                if mp.hasPrefix(dataPrefix + "/") { blocked.insert(String(mp.dropFirst(dataPrefix.count))) }
            }
        }
        return blocked
    }

    /// 扫描器遍历时固定跳过的路径(/Volumes、firmlink 入口、云盘目录等)
    static func isSkippedPath(_ path: String) -> Bool {
        skipPaths.contains(path) || cloudPaths.contains(path)
    }

    /// 要跳过的路径,按“父目录 → 名字集合”索引:遍历时只有父目录命中才需要比较,不用给每个条目拼路径
    private static let skipByParent: [String: Set<String>] = {
        var m: [String: Set<String>] = [:]
        for p in skipPaths.union(cloudPaths) {
            let ns = p as NSString
            m[ns.deletingLastPathComponent, default: []].insert(ns.lastPathComponent)
        }
        return m
    }()

    private var path = ""
    private var extTotals: [String: ExtTotal] = [:]
    /// 扫描到的所有文件按扩展名的精确总表(每个目录合并一次,开销很小)
    var exactExts: [String: ExtTotal] { lock.lock(); defer { lock.unlock() }; return extTotals }
    private func mergeExts(_ local: [String: ExtTotal]) {
        lock.lock()
        for (k, v) in local {
            var t = extTotals[k] ?? ExtTotal()
            t.bytes += v.bytes
            t.count += v.count
            extTotals[k] = t
        }
        lock.unlock()
    }
    var scannedBytes: Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
    /// 当前正在扫描的目录(用于扫描动画下方的实时显示)
    var currentPath: String { lock.lock(); defer { lock.unlock() }; return path }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    /// 扫描是否被中途取消(此时得到的树是不完整的)
    var wasCancelled: Bool { isCancelled }

    /// 因为权限不足(EPERM/EACCES,通常是没有“完全磁盘访问权限”)而打不开的目录数,以及前几个样例路径。
    /// 这些目录按 0 字节计入,所以扫描结果会偏小。
    private var deniedCount = 0
    private var deniedSamples: [String] = []
    var unreadable: (count: Int, samples: [String]) {
        lock.lock(); defer { lock.unlock() }
        return (deniedCount, deniedSamples)
    }
    private func noteDenied(_ path: String) {
        lock.lock()
        deniedCount += 1
        if deniedSamples.count < 5 { deniedSamples.append(path) }
        lock.unlock()
    }
    private func add(_ n: Int64) { lock.lock(); bytes += n; lock.unlock() }

    func scan(_ url: URL) -> Node {
        computeBlockedMounts(root: url)
        let root = Node(url: url, isDir: true)
        let entries = list(url)
        var results = [Node?](repeating: nil, count: entries.count)
        let resultLock = NSLock()

        // 目录并行扫描,充分利用多核;文件直接处理
        let group = DispatchGroup()
        for (i, e) in entries.enumerated() {
            if e.isDir {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    self.buildAsync(e.url, inApp: false, depth: 1) { n in
                        resultLock.lock(); results[i] = n; resultLock.unlock()
                        group.leave()
                    }
                }
            } else {
                let n = build(e.url, isDir: false, size: e.size, mod: e.mod, inApp: false)
                // 异步目录任务也在写 results,必须同一把锁,否则是对 Array 的并发写
                resultLock.lock(); results[i] = n; resultLock.unlock()
            }
        }
        group.wait()
        resultLock.lock()
        let top = results.compactMap { $0 }
        resultLock.unlock()
        var cats = [Int64](repeating: 0, count: Category.count)
        for n in top {
            let t = n.categoryTotals(inApp: false)
            for i in 0..<Category.count { cats[i] += t[i] }
        }
        root.cats = cats
        root.extTotals = exactExts
        finish(root, kids: top)
        return root
    }

    /// `extraSmall`:调用方已经直接累加、没有建节点的小文件字节数
    private func finish(_ node: Node, kids: [Node], extraSmall: Int64 = 0) {
        var total: Int64 = extraSmall
        var small: Int64 = extraSmall
        var kept: [Node] = []
        for k in kids {
            total += k.size
            if k.size >= threshold { k.parent = node; k.releaseURL(); kept.append(k) } else { small += k.size }
        }
        if small > 0 {
            let agg = Node(name: "小文件 / Small items", isDir: false, size: small)
            agg.isAggregate = true
            agg.parent = node
            kept.append(agg)
        }
        node.size = total
        node.children = kept.sorted { $0.size > $1.size }
    }

    /// 这一层以内的子目录并行扫描。以前只有第一层并行,从 "/" 扫描时占 63% 的 Users 整棵树都是单线程,
    /// 12 个核平均只用了不到 1 个;再往深处分叉就只是调度开销,所以设个上限,更深的在当前线程里顺序扫。
    /// 注意不能用嵌套的 concurrentPerform:GCD 会把内层压成单线程,实测完全没有加速。
    private static let parallelDepth = 6

    /// 一个目录本层的扫描结果:本层文件已经统计完,子目录还没进去
    private struct Level {
        var cats: [Int64]
        var kids: [Node]
        var smallBytes: Int64
        var dirs: [Entry]
        let inApp: Bool
    }

    /// 列出一个目录,统计本层的文件(子目录留给调用方递归)
    private func scanLevel(_ url: URL, inApp parentInApp: Bool) -> Level {
        lock.lock(); path = url.path; lock.unlock()
        // .app 包里的所有文件都算“应用程序”
        let inApp = parentInApp || url.pathExtension.lowercased() == "app"
        var lv = Level(cats: [Int64](repeating: 0, count: Category.count), kids: [], smallBytes: 0, dirs: [], inApp: inApp)
        var fileBytes: Int64 = 0
        var localExts: [String: ExtTotal] = [:]
        for e in list(url) {
            if e.isDir { lv.dirs.append(e); continue }
            fileBytes += e.size
            let ext = (e.name as NSString).pathExtension.lowercased()
            localExts[ext, default: ExtTotal()].add(e.size)
            lv.cats[Category.of(ext: ext, inApp: inApp).rawValue] += e.size
            // 小文件最后都会被合并掉,所以根本不建节点——扫描时的峰值内存因此小得多
            if e.size >= threshold {
                let fileNode = Node(url: e.url, isDir: false, size: e.size)
                fileNode.mod = e.mod
                lv.kids.append(fileNode)
            } else {
                lv.smallBytes += e.size
            }
        }
        add(fileBytes)
        mergeExts(localExts)
        return lv
    }

    /// 子目录都扫完后收尾:合并类别、建 Small items、排序
    private func complete(_ node: Node, _ lv: Level, subs: [Node?]) {
        var cats = lv.cats
        var kids = lv.kids
        for c in subs {
            guard let c else { continue }
            if c.cats.count == Category.count {
                for i in 0..<Category.count { cats[i] += c.cats[i] }
            }
            kids.append(c)
        }
        node.cats = cats
        finish(node, kids: kids, extraSmall: lv.smallBytes)
    }

    /// 顺序版本:整棵子树在当前线程里扫完
    private func build(_ url: URL, isDir: Bool, size: Int64, mod: Date? = nil, inApp: Bool) -> Node {
        let node = Node(url: url, isDir: isDir, size: size)
        node.mod = isDir ? nil : mod
        if !isDir {
            add(size)
            mergeExts([extKey(url): ExtTotal(bytes: size, count: 1)])
            return node
        }
        if isCancelled { return node }
        let lv = scanLevel(url, inApp: inApp)
        var subs = [Node?]()
        subs.reserveCapacity(lv.dirs.count)
        for e in lv.dirs {
            if isCancelled { break }
            subs.append(build(e.url, isDir: true, size: 0, inApp: lv.inApp))
        }
        complete(node, lv, subs: subs)
        return node
    }

    /// 某个目录还在等多少个子目录
    private final class Pending: @unchecked Sendable {
        let lock = NSLock()
        var remaining: Int
        var subs: [Node?]
        init(_ n: Int) { remaining = n; subs = [Node?](repeating: nil, count: n) }
    }

    /// 并行版本:每个子目录作为独立任务丢进全局队列,最后一个完成的子目录负责收尾父目录。
    /// 不阻塞任何线程,所以不会因为等待而耗尽线程池。
    private func buildAsync(_ url: URL, inApp: Bool, depth: Int, done: @escaping @Sendable (Node) -> Void) {
        let node = Node(url: url, isDir: true, size: 0)
        if isCancelled { done(node); return }
        let lv = scanLevel(url, inApp: inApp)
        if lv.dirs.isEmpty { complete(node, lv, subs: []); done(node); return }
        if depth >= Self.parallelDepth {
            var subs = [Node?]()
            for e in lv.dirs {
                if isCancelled { break }
                subs.append(build(e.url, isDir: true, size: 0, inApp: lv.inApp))
            }
            complete(node, lv, subs: subs)
            done(node)
            return
        }
        let pending = Pending(lv.dirs.count)
        for (i, e) in lv.dirs.enumerated() {
            DispatchQueue.global(qos: .userInitiated).async {
                self.buildAsync(e.url, inApp: lv.inApp, depth: depth + 1) { child in
                    pending.lock.lock()
                    pending.subs[i] = child
                    pending.remaining -= 1
                    let last = pending.remaining == 0
                    let subs = pending.subs
                    pending.lock.unlock()
                    if last {
                        self.complete(node, lv, subs: subs)
                        done(node)
                    }
                }
            }
        }
    }

    /// getattrlistbulk 一次系统调用返回一批条目的名字、类型、占用大小和修改时间,
    /// 比“列目录 + 每个条目单独 stat”省掉绝大部分系统调用。
    /// 文件系统不支持时(返回 ENOTSUP 之类)回退到 FileManager。
    private func list(_ url: URL) -> [Entry] {
        autoreleasepool {
            var dirPath = url.path
            if dirPath.count > 1, dirPath.hasSuffix("/") { dirPath.removeLast() }
            let fd = open(dirPath, O_RDONLY | O_DIRECTORY)
            guard fd >= 0 else {
                if errno == EPERM || errno == EACCES { noteDenied(dirPath) }
                return []
            }
            defer { close(fd) }

            var al = attrlist()
            al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
            // 返回顺序按位号:NAME → DEVID → OBJTYPE → MODTIME → FILEID;文件属性:LINKCOUNT → ALLOCSIZE。
            // 设备号 + 文件号用来给硬链接去重(见 countsLink)
            al.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
                | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
                | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID)
            al.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

            let bufSize = 128 * 1024
            let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
            defer { buf.deallocate() }
            let skip = Self.skipByParent[dirPath]
            let prefix = dirPath == "/" ? "/" : dirPath + "/"
            var out: [Entry] = []

            // vnode 类型(sys/vnode.h 没有导出到用户态)
            let vDir: UInt32 = 2, vLnk: UInt32 = 5

            while true {
                let n = getattrlistbulk(fd, &al, buf, bufSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
                if n < 0 {
                    if out.isEmpty && (errno == ENOTSUP || errno == EINVAL) { return listFallback(url) }
                    break
                }
                if n == 0 { break }
                var rec = buf
                for _ in 0..<Int(n) {
                    let recLen = Int(rec.loadUnaligned(as: UInt32.self))
                    var q = rec + 4
                    let returned = q.loadUnaligned(as: attribute_set_t.self)
                    q += MemoryLayout<attribute_set_t>.size
                    defer { rec += recLen }

                    guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { continue }
                    let ref = q.loadUnaligned(as: attrreference_t.self)
                    let name = String(cString: (q + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    q += MemoryLayout<attrreference_t>.size

                    // 用了 FSOPT_PACK_INVAL_ATTRS:请求的每个属性都会占位(文件系统不支持的填默认值),
                    // 所以指针必须无条件前进;`returned` 只用来判断读到的值是否有效。
                    // 以前这四项只在“已返回”时才前进:APFS 总会返回所以没事,但在不返回其中某项的文件系统上
                    //(外接盘的 exFAT、网络卷的 SMB / NFS)后面的字段会整体错位,类型和大小读成垃圾值。
                    var dev: UInt32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                        dev = q.loadUnaligned(as: UInt32.self)
                    }
                    q += 4
                    var type: UInt32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                        type = q.loadUnaligned(as: UInt32.self)
                    }
                    q += 4
                    var mod: Date?
                    if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                        let ts = q.loadUnaligned(as: timespec.self)
                        mod = Date(timeIntervalSince1970: Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9)
                    }
                    q += MemoryLayout<timespec>.size
                    var fileID: UInt64 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                        fileID = q.loadUnaligned(as: UInt64.self)
                    }
                    q += 8
                    // 文件属性同理:目录没有链接数 / 占用大小,但 4 + 8 字节照样占位
                    var linkCount: UInt32 = 1
                    if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                        linkCount = q.loadUnaligned(as: UInt32.self)
                    }
                    q += 4
                    var alloc: Int64 = 0
                    if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                        alloc = q.loadUnaligned(as: Int64.self)
                    }

                    if type == vLnk { continue }
                    if let skip, skip.contains(name) { continue }
                    let isDir = type == vDir
                    if isDir, !blockedMounts.isEmpty, blockedMounts.contains(prefix + name) { continue }
                    var size = isDir ? 0 : alloc
                    // 硬链接(同一个 inode 的多个名字)只算第一次,否则 pnpm store、Homebrew 等会被重复统计
                    if !isDir, linkCount > 1, fileID != 0, !countsLink(dev: dev, id: fileID) { size = 0 }
                    out.append(Entry(parent: url, name: name, isDir: isDir, size: size, mod: mod))
                }
            }
            return out
        }
    }

    /// 旧的列目录方式:不支持 getattrlistbulk 的文件系统走这里
    private func listFallback(_ url: URL) -> [Entry] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Self.keys, options: []) else { return [] }
        var out: [Entry] = []
        out.reserveCapacity(items.count)
        for u in items {
            var p = u.path
            if p.count > 1, p.hasSuffix("/") { p.removeLast() }
            if Self.skipPaths.contains(p) || Self.cloudPaths.contains(p) { continue }
            if blockedMounts.contains(p) { continue }
            let v = try? u.resourceValues(forKeys: Self.keySet)
            if v?.isSymbolicLink == true { continue }
            let size = Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
            out.append(Entry(parent: url, name: u.lastPathComponent, isDir: v?.isDirectory == true,
                             size: size, mod: v?.contentModificationDate))
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
                let childInApp = inApp || (c.isDir && c.isAppBundle)
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
    /// 右侧图表的显示方式(环形图 / 方块图 / 树形列表),记住上次的选择
    @Published var chartStyle: ChartStyle = ChartStyle(
        rawValue: UserDefaults.standard.string(forKey: "chartStyle") ?? "") ?? .ring {
        didSet { UserDefaults.standard.set(chartStyle.rawValue, forKey: "chartStyle") }
    }
    @Published var selectedCategory: Category? { didSet { refreshTopFiles() } }
    @Published var typeGrouping: TypeGrouping = .category {
        didSet { refreshTopFiles(); refreshExtStats() }
    }
    @Published var selectedExt: String? {       // "" = 没有扩展名
        didSet { refreshTopFiles(); refreshExtHighlight() }
    }
    @Published var extStats: [ExtStat] = []     // 按扩展名统计
    @Published var extSmallBytes: Int64 = 0     // 被合并的小文件总大小
    @Published var extExact = false             // true = 来自扫描时记录的精确总表(含所有小文件)
    /// 环形图高亮用:每个节点子树里属于所选扩展名的字节数(随所选扩展名 / 当前文件夹刷新)
    var extHighlight: [ObjectIdentifier: Int64] = [:]
    var extHighlightColor: Color = .accentColor
    @Published var topFiles: [Node] = []        // “按类型”模式下,所选类型里最大的文件
    @Published var hogs: [HogItem] = []         // “占用大户”列表
    @Published var hogsLoading = false
    /// 已保存的扫描结果(含历史快照)占用的磁盘空间,给状态栏的「清除缓存」按钮显示。
    /// 由 refreshCacheSize() 在后台统计:不能放在视图的初始值里算,那样每次重绘都会去读磁盘
    @Published var cacheSize: Int64 = 0
    @Published var unreadableCount = 0          // 上次扫描里因权限不足打不开的目录数(结果会偏小)
    @Published var unreadableSamples: [String] = []
    @Published var scanStopped = false          // 扫描被手动停止,当前结果不完整
    @Published var showDiff = false             // 显示“对比扫描”窗口
    @Published var scanDelta: ScanDelta?        // 刚完成的扫描和上一次相比的变化(用于提示条)
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
    @Published var collected: [Node] = [] {      // 收集器里的项目
        didSet { collectedPaths = collected.map { $0.url.standardizedFileURL.path } }
    }
    /// 收集器各项的标准化路径,只在收集器变化时重算一次。
    /// isCollected 每个可见行每次重绘都要调用,不能每次都为每个收集项重建 URL 再标准化
    private var collectedPaths: [String] = []
    @Published var confirmTrashCollected = false
    @Published var dragNode: Node?              // 正从环形图拖出的节点
    @Published var dragPoint: CGPoint?          // 拖动位置(root 坐标系)
    var dragging: Node?                         // 正从列表拖出的节点
    var collectorFrame: CGRect = .zero
    var revealStart = Date()
    private var revealToken = 0

    private(set) var segments: [Segment] = []
    /// 每次重算 segments 加一,环形图据此判断缓存的扇形路径是否还有效
    private(set) var segmentsVersion = 0
    private var scanner: DiskScanner?
    private var timer: Timer?

    private func rebuild() {
        segments = current.map { SunburstLayout.segments(for: $0) } ?? []
        segmentsVersion += 1
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
        // 旧扫描树马上要被换掉:所有还拿着旧节点的地方都清掉
        dragging = nil; dragNode = nil; dragPoint = nil; pendingTrash = nil
        collected = []; scanningPath = ""; selectedCategory = nil; selectedExt = nil
        isCached = false; scanDate = nil; scanStopped = false; scanDelta = nil
        unreadableCount = 0; unreadableSamples = []
        UserDefaults.standard.set(url.path, forKey: "lastTarget")
        scanning = true
        scannedBytes = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak s] _ in
            guard let s else { return }
            let v = s.scannedBytes
            let p = s.currentPath
            Task { @MainActor in
                self?.scannedBytes = v
                self?.scanningPath = p
            }
        }
        timer?.tolerance = 0.1

        Task.detached(priority: .userInitiated) { [weak self] in
            let r = s.scan(url)
            let date = Date()
            // 被取代的扫描结果会被丢弃,被停止的结果不完整、不保存:都不必白白拷一遍整棵树(峰值内存 2~3 倍)
            let stillCurrent = await MainActor.run { self?.scanner === s }
            guard stillCurrent else { return }
            // 先在后台生成可序列化的快照,界面更新后再写盘(此时 r 还没交给界面,没人会改它)
            let snap: ScanSnapshot? = s.wasCancelled
                ? nil : ScanSnapshot(path: url.path, date: date, root: ScanStore.dto(r))
            // 在写入新快照之前,取出上一次扫描的大小,用来提示“比上次多了多少”
            let prev = s.wasCancelled ? nil : ScanStore.previousSummary(for: url.path, before: date)
            let accepted = await MainActor.run { () -> Bool in
                guard let self, self.scanner === s else { return false }
                self.timer?.invalidate()
                self.root = r
                self.current = r
                self.scanDate = date
                self.isCached = false
                self.scanStopped = s.wasCancelled
                let un = s.unreadable
                self.unreadableCount = un.count
                self.unreadableSamples = un.samples
                self.scanDelta = prev.map { ScanDelta(prevDate: $0.date, prevSize: $0.size, newSize: r.size) }
                self.scanning = false
                return true
            }
            // 被取消的扫描结果不完整,不保存
            if accepted, !s.wasCancelled, let snap {
                try? ScanStore.write(snap)
                await MainActor.run { self?.refreshCacheSize() }
            }
        }
    }

    /// 在后台统计缓存目录的大小(要列目录、逐个读文件大小),算完再回主线程更新
    func refreshCacheSize() {
        Task.detached(priority: .utility) { [weak self] in
            let size = ScanStore.totalSize()
            await MainActor.run {
                if self?.cacheSize != size { self?.cacheSize = size }
            }
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
                    self.scanDate = loaded.date
                    self.isCached = true
                    // 内存被释放之前停留的文件夹:沿着名字找回去
                    var node = loaded.root
                    for name in self.pendingPath {
                        guard let next = node.children.first(where: { !$0.isAggregate && $0.name == name }) else { break }
                        node = next
                    }
                    self.pendingPath = []
                    self.current = node
                } else {
                    self.scan(url)
                }
            }
        }
    }

    // MARK: 窗口隐藏后释放内存

    /// 内存释放前所在的文件夹(从根往下的名字),重新载入后回到那里
    private var pendingPath: [String] = []
    /// 扫描结果当前是否因为窗口长时间隐藏而被释放了
    private(set) var memoryReleased = false

    /// 窗口隐藏了一段时间后调用:释放扫描树和所有由它派生的数据,只留磁盘上的缓存。
    /// 有可能丢失工作成果的情况(正在扫描 / 查找、收集器有内容、扫描被中途停止、没有缓存)一律不释放。
    func releaseMemory() {
        guard let r = root, !scanning, !scanStopped, !hogsLoading, dupState != .running,
              collected.isEmpty, !showDiff, dragNode == nil, pendingTrash == nil,
              FileManager.default.fileExists(atPath: ScanStore.fileURL(for: r.url.path).path)
        else { return }
        pendingPath = trail.dropFirst().map { $0.name }
        hovered = nil
        dragging = nil
        topFiles = []; bigFiles = []; extStats = []; extHighlight = [:]
        scanner = nil          // 连同它保存的扩展名总表一起释放
        current = nil          // 触发 rebuild():环形图分段清空
        root = nil
        memoryReleased = true
        malloc_zone_pressure_relief(nil, 0)   // 让系统马上收回释放掉的内存页
    }

    /// 窗口重新显示时调用:如果内存被释放过,从缓存载回来
    func restoreIfReleased() {
        guard memoryReleased else { return }
        memoryReleased = false
        loadCachedOrScan()
    }

    /// 停止当前扫描:已扫到的部分会保留并显示,但标记为不完整,也不会保存为缓存
    func stopScan() {
        guard scanning, let s = scanner else { return }
        s.cancel()
        scanStopped = true
    }

    /// 清理(移到废纸篓)之后,把更新后的结果重新存盘,日期保持为原扫描时间
    /// 连续清理时只存一次:每次调用重新计时,安静下来之后才生成快照并写盘。
    /// (以前每清理一项就在主线程把整棵树拷一遍,几十万节点时界面会卡住好几秒)
    private func saveCache() {
        saveCacheTask?.cancel()
        saveCacheTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self,
                  let r = self.root, !self.scanning, !self.scanStopped else { return }
            // 快照必须在主线程拍(树只有主线程在改);编码和写盘在后台
            let snap = ScanSnapshot(path: r.url.path, date: self.scanDate ?? Date(), root: ScanStore.dto(r))
            Task.detached(priority: .utility) { [weak self] in
                try? ScanStore.writeLatest(snap)
                await MainActor.run { self?.refreshCacheSize() }
            }
        }
    }
    private var saveCacheTask: Task<Void, Never>?

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
            // 路径已经无从得知的节点(见 Node.isOrphan)绝不能拿去删
            if n.isOrphan {
                failures.append("\(n.name): " + tr("找不到这个项目的位置,请重新扫描", "its location is no longer known; please rescan"))
                collected.removeAll { $0 === n }
                continue
            }
            do {
                try FileManager.default.trashItem(at: n.url, resultingItemURL: nil)
                // 占用大户这类独立节点不在扫描树里:按路径找到树里对应的节点再摘除
                if n.parent != nil {
                    detach(n)
                } else if let target = findInTree(n.url) {
                    detach(target)
                } else {
                    detachUntracked(n.url, size: n.size, isDir: n.isDir)
                }
                collected.removeAll { urlIsInside($0.url, of: n.url) }
            } catch {
                failures.append("\(n.name): \(error.localizedDescription)")
            }
        }
        hovered = nil
        recoverCurrent()
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
                    walk(c, inApp: inApp || c.isAppBundle)
                } else if let cat {
                    if Category.of(ext: c.ext, inApp: inApp) == cat { out.append(c) }
                } else if let ext {
                    if c.ext == ext { out.append(c) }
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
        if collectedPaths.isEmpty { return false }
        let p = n.url.standardizedFileURL.path
        for c in collectedPaths where p == c || p.hasPrefix(c.hasSuffix("/") ? c : c + "/") { return true }
        return false
    }

    func collect(_ n: Node) {
        guard !n.isAggregate, !n.isOrphan else { return }
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
        subtractExactExts(of: n)
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

    /// 从根节点的“精确扩展名总表”里扣掉被删除的节点。
    /// 树里只有 ≥2MB 的文件有节点;如果删的东西里还有没节点的小文件(整个文件夹、合并的小项目),
    /// 就没法知道它们各属于哪个扩展名:这时丢掉精确表,「按扩展名」改用扫描树统计,而不是继续显示过时的数字。
    private func subtractExactExts(of n: Node) {
        guard let root, root.extTotals != nil else { return }
        var known: Int64 = 0
        func walk(_ x: Node) {
            if x.isAggregate { return }
            if x.isDir { x.children.forEach(walk); return }
            known += x.size
            let k = x.ext
            if var t = root.extTotals?[k] {
                t.bytes = max(0, t.bytes - x.size)
                t.count = max(0, t.count - 1)
                if t.count == 0 && t.bytes == 0 { root.extTotals?[k] = nil } else { root.extTotals?[k] = t }
            }
        }
        walk(n)
        if n.size > known { root.extTotals = nil }
    }

    /// 被删的东西在扫描树里没有节点(例如 1~2MB 的重复文件被合并进了「小文件」):
    /// 沿路径找到树里最深的上级目录,从它的「小文件」节点和各级上级里扣掉这部分大小
    private func detachUntracked(_ url: URL, size s: Int64, isDir: Bool) {
        guard let r = root, s > 0 else { return }
        let rp = r.url.standardizedFileURL.pathComponents
        let up = url.standardizedFileURL.pathComponents
        guard up.count > rp.count, Array(up.prefix(rp.count)) == rp else { return }
        var cur = r
        for comp in up[rp.count...] {
            guard let next = cur.children.first(where: { !$0.isAggregate && $0.name == comp }) else { break }
            cur = next
        }
        // 小文件节点(如果有)跟着变小;没有的话只扣上级大小
        if let agg = cur.children.first(where: { $0.isAggregate }) {
            agg.size -= s
            if agg.size <= 0 { cur.children.removeAll { $0 === agg } }
        }
        var t = [Int64](repeating: 0, count: Category.count)
        if !isDir {
            t[Category.of(ext: extKey(url), inApp: cur.isInsideApp).rawValue] = s
            if var tot = r.extTotals?[extKey(url)] {
                tot.bytes = max(0, tot.bytes - s)
                tot.count = max(0, tot.count - 1)
                r.extTotals?[extKey(url)] = tot
            }
        } else {
            r.extTotals = nil
        }
        var p: Node? = cur
        while let q = p {
            q.size = max(0, q.size - s)
            if q.cats.count == Category.count {
                for i in 0..<Category.count { q.cats[i] = max(0, q.cats[i] - t[i]) }
            }
            p = q.parent
        }
    }

    /// 当前所在的文件夹如果已被摘除(它自己或某个上级被移进了废纸篓),回到最近的还在树里的上级
    private func recoverCurrent() {
        guard let c = current else { return }
        var chain: [Node] = []
        var x: Node? = c
        while let y = x { chain.append(y); x = y.parent }
        for node in chain.reversed().dropFirst() {
            if let par = node.parent, !par.children.contains(where: { $0 === node }) {
                current = par
                return
            }
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
