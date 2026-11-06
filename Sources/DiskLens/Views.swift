import SwiftUI
import AppKit

private struct CollectorFramePref: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var vm = ViewModel()

    private var overCollector: Bool {
        vm.dragPoint.map { vm.collectorFrame.contains($0) } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isCached, let d = vm.scanDate {
                cacheBanner(d)
                Divider()
            }
            Group {
                if let cur = vm.current {
                    HSplitView {
                        FileListView(vm: vm, node: cur)
                            .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
                        SunburstView(vm: vm, current: cur)
                            .frame(minWidth: 420)
                    }
                } else if vm.scanning {
                    ScanningView(vm: vm)
                } else {
                    Text("选择一个文件夹开始扫描")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            CollectorView(vm: vm, highlighted: overCollector)
                .background(GeometryReader { g in
                    Color.clear.preference(key: CollectorFramePref.self,
                                           value: g.frame(in: .named("root")))
                })
                .onPreferenceChange(CollectorFramePref.self) { vm.collectorFrame = $0 }
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 640)
        .coordinateSpace(name: "root")
        .overlay(alignment: .topLeading) {
            // 从环形图拖出时跟随鼠标的小标签
            if let n = vm.dragNode, let p = vm.dragPoint {
                HStack(spacing: 6) {
                    Image(systemName: n.isDir ? "folder.fill" : "doc")
                    Text(n.name).lineLimit(1).frame(maxWidth: 160)
                    Text(formatSize(n.size)).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4)
                .position(x: p.x + 20, y: p.y + 20)
                .allowsHitTesting(false)
            }
        }
        .onAppear { vm.loadCachedOrScan() }
        .alert("移到废纸篓?", isPresented: Binding(
            get: { vm.pendingTrash != nil },
            set: { if !$0 { vm.pendingTrash = nil } })
        ) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) {
                if let n = vm.pendingTrash { vm.trash(n) }
            }
        } message: {
            if let n = vm.pendingTrash {
                Text("\(n.name)(\(formatSize(n.size)))\n可在废纸篓中恢复。")
            }
        }
        .alert("清理收集器中的 \(vm.collected.count) 个项目?", isPresented: $vm.confirmTrashCollected) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓 (\(formatSize(vm.collectedSize)))", role: .destructive) {
                vm.trashItems(vm.collected)
            }
        } message: {
            Text("这些项目会被移到废纸篓,可在废纸篓中恢复。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("选择文件夹…") { chooseFolder() }
            Button("扫描整个磁盘") { vm.scan(URL(fileURLWithPath: "/")) }
            Button("个人文件夹") { vm.scan(FileManager.default.homeDirectoryForCurrentUser) }
            Button {
                vm.scan(vm.target)
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(vm.scanning)

            Divider().frame(height: 16)

            // 面包屑
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(vm.trail) { n in
                        Button(n.name) { vm.current = n }
                            .buttonStyle(.link)
                        if n !== vm.trail.last {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func cacheBanner(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
            Text("显示的是 \(date.formatted(date: .abbreviated, time: .shortened))(\(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())))保存的扫描结果,之后磁盘可能已有变化。")
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button("重新扫描") { vm.scan(vm.target) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            CapacityBar()
            Spacer()
            Button("部分目录打不开?授予「完全磁盘访问权限」") {
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(u)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { vm.scan(u) }
    }
}

// MARK: - 扫描动画

private func arcPath(center: CGPoint, radius: CGFloat, from a0: Double, to a1: Double) -> Path {
    var p = Path()
    let n = max(2, Int(abs(a1 - a0) / 0.05) + 1)
    for i in 0...n {
        let a = a0 + (a1 - a0) * Double(i) / Double(n)
        let pt = CGPoint(x: center.x + radius * CGFloat(sin(a)), y: center.y - radius * CGFloat(cos(a)))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
}

struct ScanningView: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let g = RingGeometry(size: size)
                        let lineWidth = max(2, g.w - 6)
                        for lvl in 1...SunburstLayout.maxLevel {
                            let r = g.r0 + (CGFloat(lvl) - 0.5) * g.w
                            // 底轨
                            ctx.stroke(arcPath(center: g.center, radius: r, from: 0, to: 2 * .pi),
                                       with: .color(Color.secondary.opacity(0.12)),
                                       lineWidth: lineWidth)
                            // 旋转的彩色弧段,相邻圈方向相反、速度不同
                            let dir: Double = lvl % 2 == 0 ? -1 : 1
                            let speed = dir * (0.5 + 0.25 * Double(lvl))
                            for k in 0..<3 {
                                let start = t * speed + Double(k) * 2.1 + Double(lvl)
                                let len = 0.55 + 0.4 * sin(t * 1.3 + Double(k + lvl))
                                let hue = fmod(0.58 + 0.137 * Double(k + lvl), 1.0)
                                ctx.stroke(arcPath(center: g.center, radius: r, from: start, to: start + len),
                                           with: .color(Color(hue: hue, saturation: 0.55, brightness: 0.92)),
                                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            }
                        }
                    }
                }
                VStack(spacing: 2) {
                    Text("已统计")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatSize(vm.scannedBytes))
                        .font(.title2.monospacedDigit().weight(.semibold))
                }
            }
            .frame(maxWidth: 420, maxHeight: 420)

            Text(vm.scanningPath.isEmpty ? vm.target.path : vm.scanningPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 左侧文件列表

struct FileListView: View {
    @ObservedObject var vm: ViewModel
    let node: Node

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(node.name).font(.headline).lineLimit(1)
                Spacer()
                Text(formatSize(node.size)).font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Picker("", selection: $vm.viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            Divider()
            if vm.viewMode == .folders {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(node.children) { c in
                            row(c)
                        }
                    }
                }
            } else if let cat = vm.selectedCategory {
                HStack {
                    Button {
                        vm.selectedCategory = nil
                    } label: {
                        Label("全部类型", systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                    Spacer()
                    Image(systemName: cat.icon).foregroundStyle(cat.color)
                    Text("\(cat.title) · 最大的 \(vm.topFiles.count) 个文件")
                        .font(.callout)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.topFiles) { c in
                            row(c).help(c.url.path)
                        }
                    }
                }
                Text("只统计 2MB 以上的文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            } else {
                CategoryListView(vm: vm, node: node)
            }
        }
    }

    private func row(_ c: Node) -> some View {
        let inCollector = vm.isCollected(c)
        return HStack(spacing: 8) {
            Image(systemName: inCollector ? "tray.full.fill"
                  : (c.isAggregate ? "square.stack.3d.up" : (c.isDir ? "folder.fill" : "doc")))
                .foregroundStyle(inCollector || c.isDir ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).lineLimit(1).truncationMode(.middle)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(Color.accentColor.opacity(0.8))
                            .frame(width: g.size.width * CGFloat(Double(c.size) / Double(max(node.size, 1))))
                    }
                }
                .frame(height: 4)
            }
            Text(formatSize(c.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            if !c.isAggregate {
                Button { vm.collect(c) } label: { Image(systemName: "tray.and.arrow.down") }
                    .buttonStyle(.borderless).help("加入收集器(也可以直接拖到下方收集器)")
                Button { vm.reveal(c) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("在 Finder 中显示")
                Button { vm.pendingTrash = c } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("移到废纸篓")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(vm.hovered === c ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { vm.open(c) }
        .onHover { inside in
            if inside { vm.hovered = c } else if vm.hovered === c { vm.hovered = nil }
        }
        .onDrag {
            vm.dragging = c
            return NSItemProvider(object: c.name as NSString)
        }
        .contextMenu {
            if !c.isAggregate {
                Button("加入收集器") { vm.collect(c) }
                Button("在 Finder 中显示") { vm.reveal(c) }
                Button("移到废纸篓…", role: .destructive) { vm.pendingTrash = c }
            }
        }
    }
}

// MARK: - 底部收集器

struct CollectorView: View {
    @ObservedObject var vm: ViewModel
    let highlighted: Bool
    @State private var dropTargeted = false

    private var active: Bool { highlighted || dropTargeted }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: vm.collected.isEmpty ? "tray" : "tray.full.fill")
                    .font(.title2)
                Text("收集器").font(.caption)
            }
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .frame(width: 56)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? Color.accentColor.opacity(0.1) : Color.clear)
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(active ? Color.accentColor : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                if vm.collected.isEmpty {
                    Text("把文件或文件夹拖到这里,攒够了再一次性清理")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.collected) { n in chip(n) }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .frame(height: 56)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatSize(vm.collectedSize))
                    .font(.title3.monospacedDigit().weight(.semibold))
                HStack(spacing: 8) {
                    Button("清空") { vm.clearCollector() }
                        .disabled(vm.collected.isEmpty)
                    Button(role: .destructive) {
                        vm.confirmTrashCollected = true
                    } label: {
                        Label("移到废纸篓", systemImage: "trash")
                    }
                    .disabled(vm.collected.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onDrop(of: [.plainText], isTargeted: $dropTargeted) { _ in
            if let n = vm.dragging { vm.collect(n); vm.dragging = nil }
            return true
        }
    }

    private func chip(_ n: Node) -> some View {
        HStack(spacing: 6) {
            Image(systemName: n.isDir ? "folder.fill" : "doc")
                .foregroundStyle(.secondary)
            Text(n.name).lineLimit(1).frame(maxWidth: 140)
            Text(formatSize(n.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { vm.uncollect(n) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.quaternary))
    }
}

// MARK: - 右侧环形图

struct SunburstView: View {
    @ObservedObject var vm: ViewModel
    let current: Node
    @State private var dragActive = false

    var body: some View {
        GeometryReader { geo in
            let g = RingGeometry(size: geo.size)
            let origin = geo.frame(in: .named("root")).origin
            ZStack {
                // 展开动画:扇形按角度从 12 点方向顺时针“扫开”
                TimelineView(.animation(minimumInterval: nil, paused: !vm.revealing)) { tl in
                    Canvas { ctx, _ in
                        let elapsed = tl.date.timeIntervalSince(vm.revealStart)
                        let p = vm.revealing ? min(1, max(0, elapsed / 0.7)) : 1
                        let eased = 1 - pow(1 - p, 3)
                        let limit = eased * 2 * Double.pi
                        for s in vm.segments {
                            if s.a0 >= limit { continue }
                            var clipped = s
                            clipped.a1 = min(s.a1, limit)
                            let path = g.path(for: clipped)
                            let isHover = vm.hovered === s.node
                            let fillColor = vm.viewMode == .types
                                ? SunburstLayout.typeColor(s, hovered: isHover, selected: vm.selectedCategory)
                                : SunburstLayout.color(s, hovered: isHover)
                            ctx.fill(path, with: .color(fillColor))
                            ctx.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1)
                        }
                    }
                }
                centerLabel(g)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in tap(v.location, g) })
            // 从环形图直接拖到下方收集器
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        if !dragActive {
                            dragActive = true
                            if let n = node(at: v.startLocation, g), !n.isAggregate {
                                vm.dragNode = n
                            }
                        }
                        if vm.dragNode != nil {
                            vm.dragPoint = CGPoint(x: origin.x + v.location.x,
                                                   y: origin.y + v.location.y)
                        }
                    }
                    .onEnded { _ in
                        if let n = vm.dragNode, let p = vm.dragPoint,
                           vm.collectorFrame.contains(p) {
                            vm.collect(n)
                        }
                        vm.dragNode = nil
                        vm.dragPoint = nil
                        dragActive = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let n = node(at: p, g)
                    if vm.hovered !== n { vm.hovered = n }
                case .ended:
                    if vm.hovered != nil { vm.hovered = nil }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if vm.viewMode == .types { TypeLegend(vm: vm, node: current) }
        }
    }

    private func node(at p: CGPoint, _ g: RingGeometry) -> Node? {
        guard case .ring(let level, let angle) = g.hit(p) else { return nil }
        return vm.segments.first { $0.level == level && angle >= $0.a0 && angle < $0.a1 }?.node
    }

    private func tap(_ p: CGPoint, _ g: RingGeometry) {
        switch g.hit(p) {
        case .center: vm.goUp()
        case .outside: break
        case .ring:
            if let n = node(at: p, g) { vm.open(n) }
        }
    }

    private func centerLabel(_ g: RingGeometry) -> some View {
        let shown = vm.hovered ?? current
        return VStack(spacing: 2) {
            if current.parent != nil && vm.hovered == nil {
                Image(systemName: "arrow.up.circle").foregroundStyle(.secondary)
            }
            Text(shown.name)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(formatSize(shown.size))
                .font(.title3.monospacedDigit())
        }
        .frame(width: g.r0 * 1.6)
        .position(g.center)
        .allowsHitTesting(false)
    }
}
