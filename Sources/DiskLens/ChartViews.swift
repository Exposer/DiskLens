import SwiftUI
import AppKit

// 右侧图表的三种显示方式(环形图 / 方块图 / 树形列表),以及扫描时的“磁头读盘”动画。

// MARK: - 显示方式

enum ChartStyle: String, CaseIterable, Identifiable {
    case ring, treemap, tree
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ring: return tr("环形图", "Ring")
        case .treemap: return tr("方块图", "Squares")
        case .tree: return tr("树形列表", "Tree")
        }
    }

    var icon: String {
        switch self {
        case .ring: return "chart.pie"
        case .treemap: return "square.grid.2x2"
        case .tree: return "list.bullet.indent"
        }
    }
}

extension ViewModel {
    /// 扇形 / 方块的颜色:文件夹模式按文件夹着色;文件类型模式按类别 / 所选扩展名着色
    func segmentColor(_ s: Segment, hovered: Bool) -> Color {
        guard viewMode == .types else { return SunburstLayout.color(s, hovered: hovered) }
        switch typeGrouping {
        case .category:
            return SunburstLayout.typeColor(s, hovered: hovered, selected: selectedCategory)
        case .byExtension:
            if selectedExt != nil {
                return SunburstLayout.extColor(s, hovered: hovered,
                                               bytes: extHighlight[s.node.id] ?? 0,
                                               color: extHighlightColor)
            }
            return SunburstLayout.typeColor(s, hovered: hovered, selected: nil)
        }
    }
}

/// 右侧区域:顶部切换显示方式,下面是对应的图表
struct ChartPane: View {
    @ObservedObject var vm: ViewModel
    let current: Node

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $vm.chartStyle) {
                    ForEach(ChartStyle.allCases) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(tr("切换显示方式", "Switch the display style"))
                if vm.chartStyle != .ring {
                    Button {
                        vm.goUp()
                    } label: {
                        Label(tr("上一级", "Up"), systemImage: "arrow.up")
                    }
                    .disabled(current.parent == nil)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            switch vm.chartStyle {
            case .ring: SunburstView(vm: vm, current: current)
            case .treemap: TreemapView(vm: vm, current: current)
            case .tree: TreeListView(vm: vm, current: current).id(current.id)
            }
        }
        .frame(minWidth: 420)
    }
}

// MARK: - 方块图(treemap)

struct TreeCell {
    let node: Node
    let rect: CGRect
    let level: Int
    let hue: Double
    let cats: [Int64]
    let dominant: Category
    let hasChildren: Bool      // 里面还画了下一层
}

enum TreemapLayout {
    static let maxLevel = 3
    private static let header: CGFloat = 16

    static func cells(for root: Node, in rect: CGRect) -> [TreeCell] {
        var out: [TreeCell] = []
        func place(_ n: Node, _ r: CGRect, _ level: Int, _ hue: Double?, _ inApp: Bool) {
            let kids = n.children.filter { $0.size > 0 }.prefix(300)
            guard !kids.isEmpty, r.width > 1, r.height > 1 else { return }
            let rects = squarify(kids.map { Double($0.size) }, in: r)
            for (i, c) in kids.enumerated() {
                let cr = rects[i]
                if cr.width < 2 || cr.height < 2 { continue }       // 太小的方块不画
                let h = hue ?? fmod(0.58 + Double(i) * 0.137, 1.0)
                let totals = c.categoryTotals(inApp: inApp)
                var best = Category.other
                var bestBytes: Int64 = 0
                for cat in Category.allCases where totals[cat.rawValue] > bestBytes {
                    best = cat; bestBytes = totals[cat.rawValue]
                }
                let childInApp = inApp || (c.isDir && c.isAppBundle)
                let nested = c.isDir && !c.children.isEmpty && level < maxLevel
                    && cr.width > 60 && cr.height > 48
                out.append(TreeCell(node: c, rect: cr, level: level, hue: h, cats: totals,
                                    dominant: best, hasChildren: nested))
                if nested {
                    let inner = CGRect(x: cr.minX + 2, y: cr.minY + header,
                                       width: cr.width - 4, height: cr.height - header - 2)
                    place(c, inner, level + 1, h, childInApp)
                }
            }
        }
        place(root, rect, 1, nil, root.isInsideApp)
        return out
    }

    /// Squarified treemap:`sizes` 从大到小,返回等长的矩形,面积与 sizes 成正比
    static func squarify(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: sizes.count)
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { $0 * scale }
        var r = rect
        var i = 0
        while i < areas.count {
            let side = Double(min(r.width, r.height))
            guard side > 0 else { break }
            func worst(_ sum: Double, _ mx: Double, _ mn: Double) -> Double {
                max(side * side * mx / (sum * sum), sum * sum / (side * side * mn))
            }
            var sum = 0.0
            var best = Double.infinity
            var end = i
            while end < areas.count {
                let s = sum + areas[end]
                let w = worst(s, areas[i], max(areas[end], 1e-9))
                if w > best { break }
                best = w; sum = s; end += 1
            }
            if end == i { end = i + 1; sum = areas[i] }
            let thickness = CGFloat(sum / side)
            if r.width >= r.height {
                var y = r.minY
                for k in i..<end {
                    let h = CGFloat(areas[k]) / max(thickness, 1e-6)
                    result[k] = CGRect(x: r.minX, y: y, width: thickness, height: h)
                    y += h
                }
                r = CGRect(x: r.minX + thickness, y: r.minY,
                           width: max(0, r.width - thickness), height: r.height)
            } else {
                var x = r.minX
                for k in i..<end {
                    let w = CGFloat(areas[k]) / max(thickness, 1e-6)
                    result[k] = CGRect(x: x, y: r.minY, width: w, height: thickness)
                    x += w
                }
                r = CGRect(x: r.minX, y: r.minY + thickness,
                           width: r.width, height: max(0, r.height - thickness))
            }
            i = end
        }
        return result
    }
}

/// 缓存方块布局:只有换了文件夹 / 清理了文件 / 窗口大小变了才重算,悬停时直接复用
final class TreemapCache {
    private var version = -1
    private var size = CGSize.zero
    private(set) var cells: [TreeCell] = []

    func cells(for root: Node, version v: Int, size s: CGSize) -> [TreeCell] {
        if v != version || s != size {
            cells = TreemapLayout.cells(for: root, in: CGRect(origin: .zero, size: s).insetBy(dx: 8, dy: 8))
            version = v
            size = s
        }
        return cells
    }

    func node(at p: CGPoint) -> Node? {
        cells.last { $0.rect.contains(p) }?.node      // 后面的是更深一层,优先命中
    }
}

struct TreemapView: View {
    @ObservedObject var vm: ViewModel
    let current: Node
    @State private var cache = TreemapCache()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in
                    let cells = cache.cells(for: current, version: vm.segmentsVersion, size: size)
                    let gap = Prefs.theme.bg
                    for c in cells {
                        let r = c.rect.insetBy(dx: 0.5, dy: 0.5)
                        let seg = Segment(node: c.node, level: c.level, a0: 0, a1: 0,
                                          hue: c.hue, cats: c.cats, dominant: c.dominant)
                        let hovered = vm.hovered === c.node
                        ctx.fill(Path(r), with: .color(vm.segmentColor(seg, hovered: hovered)))
                        ctx.stroke(Path(r), with: .color(gap), lineWidth: 1)
                    }
                    // 名字:放在方块左上角,超出方块的部分裁掉
                    for c in cells where c.rect.width > 46 && c.rect.height > 16 {
                        var layer = ctx
                        layer.clip(to: Path(c.rect))
                        let name = Text(c.node.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.black.opacity(0.78))
                        layer.draw(name, at: CGPoint(x: c.rect.minX + 4, y: c.rect.minY + 2),
                                   anchor: .topLeading)
                        if !c.hasChildren && c.rect.height > 32 {
                            let sz = Text(formatSize(c.node.size))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundColor(.black.opacity(0.55))
                            layer.draw(sz, at: CGPoint(x: c.rect.minX + 4, y: c.rect.minY + 16),
                                       anchor: .topLeading)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    if let n = cache.node(at: v.location) { vm.open(n) }
                })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        let n = cache.node(at: p)
                        if vm.hovered !== n { vm.hovered = n }
                    case .ended:
                        if vm.hovered != nil { vm.hovered = nil }
                    }
                }
                .contextMenu {
                    if let n = vm.hovered, !n.isAggregate {
                        Button(tr("加入收集器", "Add to Collector")) { vm.collect(n) }
                        Button(tr("在 Finder 中显示", "Reveal in Finder")) { vm.reveal(n) }
                        Button(tr("移到废纸篓…", "Move to Trash…"), role: .destructive) { vm.pendingTrash = n }
                    }
                }

                let shown = vm.hovered ?? current
                HStack(spacing: 8) {
                    Text(shown.displayName).lineLimit(1)
                    Text(formatSize(shown.size)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 10)
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - 树形列表

struct TreeListView: View {
    @ObservedObject var vm: ViewModel
    let current: Node
    @State private var expanded: Set<ObjectIdentifier> = []

    private struct Row: Identifiable {
        let node: Node
        let depth: Int
        var id: ObjectIdentifier { node.id }
    }

    /// 只展开用户点开的节点,其余不遍历,大树也很快
    private func rows() -> [Row] {
        var out: [Row] = []
        func walk(_ n: Node, _ depth: Int) {
            for c in n.children {
                out.append(Row(node: c, depth: depth))
                if c.isDir && expanded.contains(c.id) { walk(c, depth + 1) }
            }
        }
        walk(current, 0)
        return out
    }

    var body: some View {
        let list = rows()
        let total = max(current.size, 1)
        VStack(spacing: 0) {
            HStack {
                Text(current.displayName).font(.headline).lineLimit(1)
                Spacer()
                Text(formatSize(current.size)).font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(list) { r in row(r, total: total) }
                }
            }
        }
    }

    private func row(_ r: Row, total: Int64) -> some View {
        let c = r.node
        let canExpand = c.isDir && !c.children.isEmpty
        let isOpen = expanded.contains(c.id)
        let frac = Double(c.size) / Double(total)
        return HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(r.depth) * 16, height: 1)
            Button {
                if isOpen { expanded.remove(c.id) } else { expanded.insert(c.id) }
            } label: {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 12)
                    .opacity(canExpand ? 1 : 0)
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            Image(systemName: c.isAggregate ? "ellipsis.circle" : (c.isDir ? "folder.fill" : "doc"))
                .foregroundStyle(c.isDir ? appAccent : Color.secondary)
                .frame(width: 16)
            Text(c.displayName).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(String(format: "%.1f%%", frac * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            Text(formatSize(c.size))
                .font(.callout.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(alignment: .leading) {
            GeometryReader { g in
                Rectangle()
                    .fill(appAccent.opacity(vm.hovered === c ? 0.28 : 0.14))
                    .frame(width: g.size.width * CGFloat(min(1, frac)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { vm.open(c) }
        .onHover { inside in
            if inside { vm.hovered = c } else if vm.hovered === c { vm.hovered = nil }
        }
        .contextMenu {
            if canExpand {
                Button(tr("打开这个文件夹", "Open this folder")) { vm.open(c) }
            }
            if !c.isAggregate {
                Button(tr("加入收集器", "Add to Collector")) { vm.collect(c) }
                Button(tr("在 Finder 中显示", "Reveal in Finder")) { vm.reveal(c) }
                Button(tr("移到废纸篓…", "Move to Trash…"), role: .destructive) { vm.pendingTrash = c }
            }
        }
    }
}

// MARK: - 扫描动画:磁头读取磁盘扇区

/// 动画状态(引用类型,在每一帧里更新):盘片转角、磁头位置、每个扇区最近一次被读到的时间
final class DiskHeadState {
    static let tracks = 16
    static func sectors(_ t: Int) -> Int { 14 + 3 * t }       // 外圈扇区更多,每个扇区长度大致相同

    var last: Double = 0
    var rot: Double = 0                    // 盘片转过的角度
    var track: Double = 6                  // 磁头所在磁道(连续值,寻道时平滑移动)
    var target: Double = 6
    var nextSeek: Double = 0
    var prevRel: Double = 0                // 上一帧磁头相对盘片的角度
    var readAt: [[Double]] = (0..<DiskHeadState.tracks).map {
        [Double](repeating: -1e9, count: DiskHeadState.sectors($0))
    }

    static let headAngle = Double.pi / 2   // 磁头在盘片右侧(3 点钟方向)
    static let spin = 5.0                  // 盘片转速,弧度 / 秒

    func advance(to now: Double) {
        if last == 0 { last = now; nextSeek = now + 0.4 }
        let dt = min(max(now - last, 0), 0.1)
        last = now
        rot += Self.spin * dt

        if now >= nextSeek {
            // 大部分时候在附近寻道,偶尔跳得很远
            let jump = Double.random(in: 0...1) < 0.25
                ? Double.random(in: 0..<Double(Self.tracks))
                : target + Double.random(in: -3...3)
            target = min(max(jump.rounded(), 0), Double(Self.tracks - 1))
            nextSeek = now + Double.random(in: 0.6...1.5)
        }
        track += (target - track) * min(1, dt * 10)

        // 磁头停稳之后才算“正在读”,把这一帧里扫过的扇区都标记上
        let rel = Self.headAngle - rot
        if abs(target - track) < 0.35 {
            let t = min(max(Int(track.rounded()), 0), Self.tracks - 1)
            let n = Self.sectors(t)
            let width = 2 * Double.pi / Double(n)
            let steps = max(1, Int(ceil(abs(prevRel - rel) / width)) + 1)
            for s in 0...steps {
                let a = prevRel + (rel - prevRel) * Double(s) / Double(steps)
                var f = a.truncatingRemainder(dividingBy: 2 * Double.pi)
                if f < 0 { f += 2 * Double.pi }
                readAt[t][min(n - 1, Int(f / width))] = now
            }
        }
        prevRel = rel
    }
}

private func diskArc(center: CGPoint, radius: CGFloat, from a0: Double, to a1: Double) -> Path {
    var p = Path()
    let n = max(1, Int(abs(a1 - a0) / 0.06) + 1)
    for i in 0...n {
        let a = a0 + (a1 - a0) * Double(i) / Double(n)
        let pt = CGPoint(x: center.x + radius * CGFloat(sin(a)), y: center.y - radius * CGFloat(cos(a)))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
}

/// 磁盘盘片 + 磁头臂:磁头在磁道间寻道,读到的扇区亮起,再沉淀成深青色的“已读”
struct DiskReadAnimation: View {
    @State private var state = DiskHeadState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSinceReferenceDate
                state.advance(to: now)
                DiskReadAnimation.draw(&ctx, size: size, now: now, state: state)
            }
        }
    }

    /// 配色:只用一组青蓝色。新读到的扇区是亮白青色的辉光,随后沉淀成深一点的青蓝
    private static func sectorColor(track t: Int, flash: Double) -> Color {
        let hue = 0.50 + 0.07 * Double(t) / Double(DiskHeadState.tracks - 1)   // 青 → 蓝,很小的渐变
        return tc(hue, 0.70 - 0.55 * flash, 0.78 + 0.22 * flash)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Double, state: DiskHeadState) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = max(20, min(size.width, size.height) / 2 - 10) * 0.82
        let hub = R * 0.30
        let tracks = DiskHeadState.tracks
        let tw = (R - hub) / CGFloat(tracks)
        let disc = CGRect(x: center.x - R, y: center.y - R, width: 2 * R, height: 2 * R)

        // 盘片:深色金属盘 + 投影,在浅色 / 深色主题下都有对比
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.32), radius: 16, x: 0, y: 8))
        shadow.fill(Path(ellipseIn: disc), with: .color(Color(white: 0.11)))
        ctx.fill(Path(ellipseIn: disc),
                 with: .radialGradient(Gradient(colors: [Color(white: 0.20), Color(white: 0.10), Color(white: 0.07)]),
                                       center: center, startRadius: hub, endRadius: R))

        // 随盘片旋转的两道反光
        var sheen = ctx
        sheen.clip(to: Path(ellipseIn: disc))
        let sheenAngle = Angle(radians: state.rot)
        sheen.fill(Path(ellipseIn: disc),
                   with: .conicGradient(Gradient(stops: [
                       .init(color: .white.opacity(0.00), location: 0.00),
                       .init(color: .white.opacity(0.10), location: 0.06),
                       .init(color: .white.opacity(0.00), location: 0.14),
                       .init(color: .white.opacity(0.00), location: 0.50),
                       .init(color: .white.opacity(0.07), location: 0.56),
                       .init(color: .white.opacity(0.00), location: 0.64),
                       .init(color: .white.opacity(0.00), location: 1.00)]),
                                        center: center, angle: sheenAngle))

        // 磁道:细细的同心圆
        for t in 0..<tracks {
            let r = hub + (CGFloat(t) + 0.5) * tw
            ctx.stroke(diskArc(center: center, radius: r, from: 0, to: 2 * .pi),
                       with: .color(.white.opacity(0.045)), lineWidth: 0.8)
        }

        // 已读 / 正在读的扇区(先画辉光,再画扇区本身)
        for t in 0..<tracks {
            let n = DiskHeadState.sectors(t)
            let width = 2 * Double.pi / Double(n)
            let r = hub + (CGFloat(t) + 0.5) * tw
            for s in 0..<n {
                let age = now - state.readAt[t][s]
                if age > 1e6 { continue }                                   // 还没读过
                let flash = max(0, 1 - age / 0.35)                           // 刚读到:很亮
                let alpha = max(0.42, 1 - max(0, age - 0.35) / 4.5)           // 然后沉淀到“已读”
                let a0 = Double(s) * width + state.rot + width * 0.08
                let arc = diskArc(center: center, radius: r, from: a0, to: a0 + width * 0.84)
                if flash > 0.02 {
                    ctx.stroke(arc, with: .color(sectorColor(track: t, flash: 1).opacity(0.35 * flash)),
                               style: StrokeStyle(lineWidth: tw + 3, lineCap: .butt))
                }
                ctx.stroke(arc, with: .color(sectorColor(track: t, flash: flash).opacity(alpha)),
                           style: StrokeStyle(lineWidth: max(1.5, tw - 3), lineCap: .butt))
            }
        }

        // 盘缘高光
        ctx.stroke(Path(ellipseIn: disc), with: .color(.white.opacity(0.16)), lineWidth: 1.2)

        // 中心轴:用窗口背景色挖空,中间放“已统计”的文字
        let hubRect = CGRect(x: center.x - hub, y: center.y - hub, width: 2 * hub, height: 2 * hub)
        ctx.fill(Path(ellipseIn: hubRect), with: .color(Prefs.theme.bg))
        ctx.stroke(Path(ellipseIn: hubRect), with: .color(Color(white: 0.5).opacity(0.45)), lineWidth: 2)
        ctx.stroke(Path(ellipseIn: hubRect.insetBy(dx: 5, dy: 5)),
                   with: .color(sectorColor(track: 6, flash: 0).opacity(0.35)), lineWidth: 1)

        // 磁头臂:支点在右上方,磁头落在当前磁道上
        let trackR = hub + (CGFloat(state.track) + 0.5) * tw
        let ha = DiskHeadState.headAngle
        let tip = CGPoint(x: center.x + trackR * CGFloat(sin(ha)), y: center.y - trackR * CGFloat(cos(ha)))
        let pivot = CGPoint(x: center.x + R * 1.06, y: center.y - R * 0.98)
        let reading = abs(state.target - state.track) < 0.35

        // 激光线:磁头到盘心,读盘时更亮
        var beam = Path()
        beam.move(to: tip)
        beam.addLine(to: CGPoint(x: center.x + hub * CGFloat(sin(ha)), y: center.y - hub * CGFloat(cos(ha))))
        ctx.stroke(beam, with: .color(sectorColor(track: 8, flash: 1).opacity(reading ? 0.35 : 0.12)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

        // 锥形的臂:支点处宽,磁头处窄
        let dx = tip.x - pivot.x, dy = tip.y - pivot.y
        let len = max(1, hypot(dx, dy))
        let nx = -dy / len, ny = dx / len
        var arm = Path()
        arm.move(to: CGPoint(x: pivot.x + nx * 6, y: pivot.y + ny * 6))
        arm.addLine(to: CGPoint(x: tip.x + nx * 1.8, y: tip.y + ny * 1.8))
        arm.addLine(to: CGPoint(x: tip.x - nx * 1.8, y: tip.y - ny * 1.8))
        arm.addLine(to: CGPoint(x: pivot.x - nx * 6, y: pivot.y - ny * 6))
        arm.closeSubpath()
        var armLayer = ctx
        armLayer.addFilter(.shadow(color: .black.opacity(0.35), radius: 5, x: 2, y: 4))
        armLayer.fill(arm, with: .linearGradient(
            Gradient(colors: [Color(white: 0.86), Color(white: 0.58)]),
            startPoint: pivot, endPoint: tip))
        // 支点
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - 11, y: pivot.y - 11, width: 22, height: 22)),
                 with: .color(Color(white: 0.30)))
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - 6.5, y: pivot.y - 6.5, width: 13, height: 13)),
                 with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.6)]),
                                       startPoint: CGPoint(x: pivot.x - 6, y: pivot.y - 6),
                                       endPoint: CGPoint(x: pivot.x + 6, y: pivot.y + 6)))
        // 磁头:读盘时发光
        let glow: CGFloat = reading ? 11 : 6
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - glow, y: tip.y - glow, width: 2 * glow, height: 2 * glow)),
                 with: .radialGradient(Gradient(colors: [sectorColor(track: 8, flash: 1).opacity(reading ? 0.65 : 0.2), .clear]),
                                       center: tip, startRadius: 0, endRadius: glow))
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 2.6, y: tip.y - 2.6, width: 5.2, height: 5.2)),
                 with: .color(.white))
    }
}
