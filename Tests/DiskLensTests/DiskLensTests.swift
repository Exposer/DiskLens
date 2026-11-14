import XCTest
@testable import DiskLens

// 纯逻辑的单元测试:不读真实磁盘,不碰界面。运行:swift test
// 注意:这里 `Category` 要写成 `DiskLens.Category`,否则会和 ObjectiveC 运行时里的同名类型冲突。
// (需要完整的 Xcode;只有命令行工具时没有 XCTest。打包脚本不会编译测试。)

final class DiskLensTests: XCTestCase {
    private let mb: Int64 = 1_048_576

    // MARK: 搭一棵假的扫描树

    private func file(_ name: String, _ megabytes: Int64) -> Node {
        Node(name: name, isDir: false, size: megabytes * mb)
    }

    /// 目录节点:大小 = 子节点之和,子节点按大小从大到小(和扫描器一致)
    private func dir(_ name: String, _ kids: [Node], rootPath: String? = nil) -> Node {
        let n: Node
        if let rootPath {
            n = Node(url: URL(fileURLWithPath: rootPath), name: name, isDir: true)
        } else {
            n = Node(name: name, isDir: true)
        }
        n.children = kids.sorted { $0.size > $1.size }
        for k in kids { k.parent = n }
        n.size = kids.reduce(Int64(0)) { $0 + $1.size }
        n.cats = [Int64](repeating: 0, count: DiskLens.Category.count)
        return n
    }

    // MARK: 节点路径

    func testNodeURLIsBuiltFromParentChain() {
        let movie = file("b.MP4", 10)
        let root = dir("root", [dir("a", [movie])], rootPath: "/tmp/dl-test")
        XCTAssertEqual(movie.url.path, "/tmp/dl-test/a/b.MP4")
        XCTAssertEqual(movie.ext, "mp4")
        XCTAssertFalse(movie.isOrphan)
        XCTAssertFalse(root.isOrphan)
    }

    /// 上级已经释放的节点不能解析成“当前目录下的同名文件”
    func testOrphanNodeResolvesToImpossiblePath() {
        let orphan = Node(name: "Documents", isDir: true)
        XCTAssertTrue(orphan.isOrphan)
        XCTAssertTrue(orphan.url.path.hasPrefix("/dev/null/"))
    }

    func testUrlIsInside() {
        let a = URL(fileURLWithPath: "/a")
        XCTAssertTrue(urlIsInside(URL(fileURLWithPath: "/a/b/c"), of: a))
        XCTAssertTrue(urlIsInside(a, of: a))
        XCTAssertFalse(urlIsInside(URL(fileURLWithPath: "/ab"), of: a))
        XCTAssertFalse(urlIsInside(a, of: URL(fileURLWithPath: "/a/b")))
    }

    // MARK: 分类

    func testCategoryOfExtension() {
        XCTAssertEqual(DiskLens.Category.of(ext: "mp4", inApp: false), .video)
        XCTAssertEqual(DiskLens.Category.of(ext: "mp4", inApp: true), .app)
        XCTAssertEqual(DiskLens.Category.of(ext: "no-such-ext", inApp: false), .other)
    }

    // MARK: 布局

    func testSquarifyKeepsCountAreaAndBounds() {
        let sizes: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let rects = TreemapLayout.squarify(sizes, in: rect)
        XCTAssertEqual(rects.count, sizes.count)

        let total = sizes.reduce(0, +)
        let area = Double(rect.width * rect.height)
        for (i, r) in rects.enumerated() {
            // 每块的面积和它的大小成正比
            XCTAssertEqual(Double(r.width * r.height), area * sizes[i] / total, accuracy: 1.0)
            XCTAssertGreaterThanOrEqual(r.minX, rect.minX - 0.01)
            XCTAssertGreaterThanOrEqual(r.minY, rect.minY - 0.01)
            XCTAssertLessThanOrEqual(r.maxX, rect.maxX + 0.01)
            XCTAssertLessThanOrEqual(r.maxY, rect.maxY + 0.01)
        }
    }

    func testSquarifyHandlesEmptyInput() {
        XCTAssertTrue(TreemapLayout.squarify([], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
    }

    func testSunburstFirstRingCoversFullCircle() {
        let root = dir("root", [file("a.bin", 50), file("b.bin", 30), file("c.bin", 20)], rootPath: "/tmp/dl-test")
        let ring1 = SunburstLayout.segments(for: root).filter { $0.level == 1 }
        XCTAssertEqual(ring1.count, 3)
        XCTAssertEqual(ring1.reduce(0.0) { $0 + ($1.a1 - $1.a0) }, 2 * Double.pi, accuracy: 1e-9)
    }

    // MARK: 对比扫描

    func testDiffFindsGrownAndNewFiles() {
        let old = dir("root", [dir("a", [file("f1.bin", 10)])], rootPath: "/tmp/dl-test")
        let new = dir("root", [dir("a", [file("f1.bin", 30), file("f2.bin", 5)])], rootPath: "/tmp/dl-test")
        let r = DiffEngine.compute(old: old, oldDate: Date(timeIntervalSince1970: 0), new: new, newDate: Date())

        XCTAssertEqual(r.delta, 25 * mb)
        XCTAssertEqual(r.files.count, 2)
        let grown = r.files.first { $0.name == "f1.bin" }
        XCTAssertEqual(grown?.delta, 20 * mb)
        XCTAssertEqual(grown?.kind, .grown)
        XCTAssertEqual(r.files.first { $0.name == "f2.bin" }?.kind, .added)
        // 层级:根下面只有文件夹 a,变化量是两者之和
        XCTAssertEqual(r.tree.count, 1)
        XCTAssertEqual(r.tree.first?.name, "a")
        XCTAssertEqual(r.tree.first?.delta, 25 * mb)
    }

    func testDiffIgnoresChangesUnderOneMegabyte() {
        let old = dir("root", [file("f.bin", 10)], rootPath: "/tmp/dl-test")
        let same = dir("root", [file("f.bin", 10)], rootPath: "/tmp/dl-test")
        let r = DiffEngine.compute(old: old, oldDate: Date(), new: same, newDate: Date())
        XCTAssertTrue(r.files.isEmpty)
        XCTAssertTrue(r.tree.isEmpty)
        XCTAssertEqual(r.delta, 0)
    }

    // MARK: 空间不足的阈值

    func testLowSpaceRules() {
        let gb: Int64 = 1_000_000_000
        // 共 500 GB,可用 40 GB(8%)
        let u = VolumeUsage(total: 500 * gb, used: 460 * gb, purgeable: 0, free: 40 * gb)
        XCTAssertFalse(LowSpaceRule.off.isLow(u))
        XCTAssertFalse(LowSpaceRule.gb20.isLow(u))
        XCTAssertTrue(LowSpaceRule.gb50.isLow(u))
        XCTAssertTrue(LowSpaceRule.pct10.isLow(u))
        // 可清除空间也算“可用”
        let withPurgeable = VolumeUsage(total: 500 * gb, used: 400 * gb, purgeable: 60 * gb, free: 40 * gb)
        XCTAssertFalse(LowSpaceRule.gb50.isLow(withPurgeable))
    }

    // MARK: 导出

    /// 以 = 开头的文件名不能被表格软件当成公式执行
    func testCSVNeutralisesFormulaLikeNames() {
        let root = dir("root", [file("=cmd.bin", 3), file("normal.bin", 4)], rootPath: "/tmp/dl-test")
        let csv = ReportBuilder.csv(root: root)
        XCTAssertTrue(csv.contains("\"'=cmd.bin\""))
        XCTAssertTrue(csv.contains("\"normal.bin\""))
    }

    // MARK: 缓存

    func testSnapshotSurvivesCompressionRoundTrip() throws {
        let root = dir("root", [dir("a", [file("big.mov", 40), file("small.zip", 3)]), file("top.dmg", 7)],
                       rootPath: "/tmp/dl-test")
        let snap = ScanSnapshot(path: "/tmp/dl-test", date: Date(timeIntervalSince1970: 1_700_000_000),
                                root: ScanStore.dto(root), unreadable: 2, unreadableSamples: ["/private/x"])

        let packed = try ScanStore.pack(snap)
        XCTAssertNotEqual(packed.first, UInt8(ascii: "{"), "写盘的数据应该是压缩过的")

        let json = try XCTUnwrap(ScanStore.unpack(packed))
        let decoded = try JSONDecoder().decode(ScanSnapshot.self, from: json)
        XCTAssertEqual(decoded.path, "/tmp/dl-test")
        XCTAssertEqual(decoded.unreadable, 2)
        XCTAssertEqual(decoded.unreadableSamples ?? [], ["/private/x"])

        let rebuilt = ScanStore.node(from: decoded.root, url: URL(fileURLWithPath: decoded.path), parent: nil)
        XCTAssertEqual(rebuilt.size, root.size)
        XCTAssertEqual(rebuilt.children.map { $0.name }, ["a", "top.dmg"])
        let big = try XCTUnwrap(rebuilt.children.first?.children.first)
        XCTAssertEqual(big.url.path, "/tmp/dl-test/a/big.mov")
        XCTAssertEqual(big.size, 40 * mb)
    }

    /// 旧版本写的未压缩 JSON 仍然要能读
    func testUnpackAcceptsPlainJSON() throws {
        let root = dir("root", [file("f.bin", 5)], rootPath: "/tmp/dl-test")
        let snap = ScanSnapshot(path: "/tmp/dl-test", date: Date(), root: ScanStore.dto(root))
        let plain = try JSONEncoder().encode(snap)
        XCTAssertEqual(ScanStore.unpack(plain), plain)
    }
}
