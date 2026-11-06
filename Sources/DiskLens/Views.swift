import SwiftUI
import AppKit

private struct CollectorFramePref: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject var vm: ViewModel
    /// 切换语言 / 配色后通知上层重建界面
    let onPrefsChange: () -> Void

    private var overCollector: Bool {
        vm.dragPoint.map { vm.collectorFrame.contains($0) } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .background(Prefs.theme.bar)
            Divider()
            if vm.isCached, let d = vm.scanDate {
                cacheBanner(d)
                Divider()
            }
            if vm.scanStopped && !vm.scanning {
                stoppedBanner
                Divider()
            }
            if let d = vm.scanDelta, !vm.scanning, !vm.scanStopped {
                deltaBanner(d)
                Divider()
            }
            Group {
                if let cur = vm.current {
                    HSplitView {
                        FileListView(vm: vm, node: cur)
                            .frame(minWidth: 340, idealWidth: 440, maxWidth: 600)
                        SunburstView(vm: vm, current: cur)
                            .frame(minWidth: 420)
                    }
                } else if vm.scanning {
                    ScanningView(vm: vm)
                } else {
                    Text(tr("选择一个文件夹开始扫描", "Choose a folder to start scanning"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            CollectorView(vm: vm, highlighted: overCollector)
                .background(Prefs.theme.bar)
                .background(GeometryReader { g in
                    Color.clear.preference(key: CollectorFramePref.self,
                                           value: g.frame(in: .named("root")))
                })
                .onPreferenceChange(CollectorFramePref.self) { vm.collectorFrame = $0 }
            Divider()
            statusBar
                .background(Prefs.theme.bar)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Prefs.theme.bg)
        .coordinateSpace(name: "root")
        .overlay(alignment: .topLeading) {
            // 从环形图拖出时跟随鼠标的小标签
            if let n = vm.dragNode, let p = vm.dragPoint {
                HStack(spacing: 6) {
                    Image(systemName: n.isDir ? "folder.fill" : "doc")
                    Text(n.displayName).lineLimit(1).frame(maxWidth: 160)
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
        .sheet(isPresented: $vm.showDiff) { DiffSheet(vm: vm) }
        .alert(tr("移到废纸篓?", "Move to Trash?"), isPresented: Binding(
            get: { vm.pendingTrash != nil },
            set: { if !$0 { vm.pendingTrash = nil } })
        ) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            Button(tr("移到废纸篓", "Move to Trash"), role: .destructive) {
                if let n = vm.pendingTrash { vm.trash(n) }
            }
        } message: {
            if let n = vm.pendingTrash {
                Text("\(n.displayName) (\(formatSize(n.size)))\n" + tr("可在废纸篓中恢复。", "You can restore it from the Trash."))
            }
        }
        .alert(tr("清理收集器中的 \(vm.collected.count) 个项目?",
                  "Clean up \(vm.collected.count) item\(vm.collected.count == 1 ? "" : "s") in the Collector?"),
               isPresented: $vm.confirmTrashCollected) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            Button(tr("移到废纸篓", "Move to Trash") + " (\(formatSize(vm.collectedSize)))", role: .destructive) {
                vm.trashItems(vm.collected)
            }
        } message: {
            Text(tr("这些项目会被移到废纸篓,可在废纸篓中恢复。",
                    "These items will be moved to the Trash and can be restored from there."))
        }
        .alert(tr("操作失败", "Operation Failed"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } })
        ) {
            Button(tr("好", "OK")) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(tr("选择文件夹…", "Choose Folder…")) { chooseFolder() }
            Button(tr("扫描整个磁盘", "Scan Whole Disk")) { vm.scan(URL(fileURLWithPath: "/")) }
            Button(tr("个人文件夹", "Home Folder")) { vm.scan(FileManager.default.homeDirectoryForCurrentUser) }
            Button {
                vm.scan(vm.target)
            } label: {
                Label(tr("重新扫描", "Rescan"), systemImage: "arrow.clockwise")
            }
            .disabled(vm.scanning)

            if vm.scanning {
                Button(role: .destructive) {
                    vm.stopScan()
                } label: {
                    Label(vm.scanStopped ? tr("正在停止…", "Stopping…") : tr("停止扫描", "Stop Scan"),
                          systemImage: "stop.fill")
                }
                .disabled(vm.scanStopped)
            }

            Divider().frame(height: 16)

            // 面包屑
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(vm.trail) { n in
                        Button(n.displayName) { vm.current = n }
                            .buttonStyle(.link)
                        if n !== vm.trail.last {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Divider().frame(height: 16)
            CompareButton(vm: vm)
            ExportMenu(vm: vm)
            SettingsMenus(onChange: onPrefsChange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func cacheBanner(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
            Text(tr("显示的是 \(formatDate(date))(\(relativeDate(date)))保存的扫描结果,之后磁盘可能已有变化。",
                    "Showing results saved on \(formatDate(date)) (\(relativeDate(date))). The disk may have changed since."))
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button(tr("重新扫描", "Rescan")) { vm.scan(vm.target) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(appAccent.opacity(0.14))
    }

    /// 扫描完成后的提示:和上一次扫描相比,总共多了 / 少了多少
    private func deltaBanner(_ d: ScanDelta) -> some View {
        let when = relativeDate(d.prevDate)
        let amount = formatSize(abs(d.delta))
        let range = "\(formatSize(d.prevSize)) → \(formatSize(d.newSize))"
        let grew = d.delta > 0
        let tint: Color = d.isUnchanged ? .secondary : (grew ? .orange : .green)
        let message: String
        if d.isUnchanged {
            message = tr("和上次扫描(\(when))相比,基本没有变化。",
                         "Practically unchanged since the last scan (\(when)).")
        } else if grew {
            message = tr("比上次扫描(\(when))多了 \(amount)(\(range))。",
                         "\(amount) more than the last scan (\(when)): \(range).")
        } else {
            message = tr("比上次扫描(\(when))少了 \(amount)(\(range))。",
                         "\(amount) less than the last scan (\(when)): \(range).")
        }
        return HStack(spacing: 8) {
            Image(systemName: d.isUnchanged ? "equal.circle.fill"
                  : (grew ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"))
                .foregroundStyle(tint)
            Text(message)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button(tr("查看差异", "See what changed")) { vm.showDiff = true }
            Button {
                vm.scanDelta = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(tr("关闭提示", "Dismiss"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14))
    }

    private var stoppedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(tr("扫描已停止,当前显示的是不完整的结果,各文件夹的大小会偏小,也不会保存。",
                    "Scan stopped. The results are incomplete, folder sizes are underestimated, and they won't be saved."))
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button(tr("重新扫描", "Rescan")) { vm.scan(vm.target) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.14))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            CapacityBar()
            Spacer()
            CacheButton(vm: vm)
            Button(tr("部分目录打不开?授予「完全磁盘访问权限」",
                      "Some folders won't open? Grant Full Disk Access")) {
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
        p.prompt = tr("扫描", "Scan")
        if p.runModal() == .OK, let u = p.url { vm.scan(u) }
    }
}

// MARK: - 清除缓存按钮

struct CacheButton: View {
    @ObservedObject var vm: ViewModel
    @State private var size: Int64 = ScanStore.totalSize()
    @State private var confirm = false

    var body: some View {
        Button {
            confirm = true
        } label: {
            Label(size > 0
                  ? tr("清除缓存 (\(formatSize(size)))", "Clear Cache (\(formatSize(size)))")
                  : tr("无缓存", "No Cache"),
                  systemImage: "trash.slash")
        }
        .buttonStyle(.link)
        .font(.caption)
        .disabled(size == 0)
        .help(tr("删除已保存的扫描结果。当前窗口里的结果不受影响,下次启动会重新扫描。",
                 "Delete saved scan results. The results in this window are unaffected; the next launch will rescan."))
        .onChange(of: vm.scanDate) { _ in
            // 扫描结果在界面更新之后才写盘,稍等一会儿再刷新大小
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                size = ScanStore.totalSize()
            }
        }
        .onAppear { size = ScanStore.totalSize() }
        .alert(tr("清除已保存的扫描结果?", "Clear saved scan results?"), isPresented: $confirm) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            Button(tr("清除", "Clear"), role: .destructive) {
                ScanStore.clearAll()
                size = ScanStore.totalSize()
            }
        } message: {
            Text(tr("只会删除 DiskLens 自己保存的缓存文件(包括用于「对比」的历史快照),不会动你的任何文件。下次启动会重新扫描。",
                    "Only DiskLens's own cache files are deleted (including the history snapshots used by Compare); none of your files are touched. The next launch will rescan."))
        }
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
                                           with: .color(tc(hue, 0.55, 0.92)),
                                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            }
                        }
                    }
                }
                VStack(spacing: 2) {
                    Text(tr("已统计", "Scanned"))
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

            Button {
                vm.stopScan()
            } label: {
                Label(vm.scanStopped ? tr("正在停止…", "Stopping…") : tr("停止扫描", "Stop Scan"),
                      systemImage: "stop.circle")
            }
            .controlSize(.large)
            .disabled(vm.scanStopped)
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
                Text(node.displayName).font(.headline).lineLimit(1)
                Spacer()
                Text(formatSize(node.size)).font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Picker("", selection: $vm.viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            Divider()
            switch vm.viewMode {
            case .folders:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(node.children) { c in
                            row(c)
                        }
                    }
                }
            case .types:
                typesPanel
            case .big:
                BigFileListView(vm: vm, node: node)
            case .hogs:
                HogListView(vm: vm)
            case .dups:
                DupListView(vm: vm)
            }
        }
    }

    // MARK: 「文件类型」页:按类别 / 按扩展名,点进去看该类型里最大的文件

    private var detailTitle: (icon: String, color: Color, title: String)? {
        switch vm.typeGrouping {
        case .category:
            guard let cat = vm.selectedCategory else { return nil }
            return (cat.icon, cat.color, cat.title)
        case .byExtension:
            guard let e = vm.selectedExt else { return nil }
            return ("doc", appAccent, extLabel(e))
        }
    }

    private func clearSelection() {
        switch vm.typeGrouping {
        case .category: vm.selectedCategory = nil
        case .byExtension: vm.selectedExt = nil
        }
    }

    @ViewBuilder
    private var typesPanel: some View {
        if let d = detailTitle {
            HStack {
                Button {
                    clearSelection()
                } label: {
                    Label(vm.typeGrouping == .category ? tr("全部类型", "All Types") : tr("全部扩展名", "All Extensions"),
                          systemImage: "chevron.left")
                }
                .buttonStyle(.link)
                Spacer()
                Image(systemName: d.icon).foregroundStyle(d.color)
                Text(tr("\(d.title) · 最大的 \(vm.topFiles.count) 个文件",
                        "\(d.title) · Top \(vm.topFiles.count) files"))
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
            Text(tr("只统计 2MB 以上的文件", "Only files of 2 MB or more are listed"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        } else {
            Picker("", selection: $vm.typeGrouping) {
                ForEach(TypeGrouping.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            switch vm.typeGrouping {
            case .category:
                CategoryListView(vm: vm, node: node)
            case .byExtension:
                ExtensionListView(vm: vm, node: node)
            }
        }
    }

    private func row(_ c: Node) -> some View {
        let inCollector = vm.isCollected(c)
        return HStack(spacing: 8) {
            Image(systemName: inCollector ? "tray.full.fill"
                  : (c.isAggregate ? "square.stack.3d.up" : (c.isDir ? "folder.fill" : "doc")))
                .foregroundStyle(inCollector || c.isDir ? appAccent : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.displayName).lineLimit(1).truncationMode(.middle)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(appAccent.opacity(0.8))
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
                    .buttonStyle(.borderless)
                    .help(tr("加入收集器(也可以直接拖到下方收集器)", "Add to Collector (or drag it onto the Collector below)"))
                Button { vm.reveal(c) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help(tr("在 Finder 中显示", "Reveal in Finder"))
                Button { vm.pendingTrash = c } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help(tr("移到废纸篓", "Move to Trash"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(vm.hovered === c ? appAccent.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { vm.open(c) }
        .onHover { inside in
            if inside { vm.hovered = c } else if vm.hovered === c { vm.hovered = nil }
        }
        .onDrag {
            vm.dragging = c
            return NSItemProvider(object: c.displayName as NSString)
        }
        .contextMenu {
            if !c.isAggregate {
                Button(tr("加入收集器", "Add to Collector")) { vm.collect(c) }
                Button(tr("在 Finder 中显示", "Reveal in Finder")) { vm.reveal(c) }
                Button(tr("移到废纸篓…", "Move to Trash…"), role: .destructive) { vm.pendingTrash = c }
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
                Text(tr("收集器", "Collector")).font(.caption)
            }
            .foregroundStyle(active ? appAccent : Color.secondary)
            .frame(width: 64)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? appAccent.opacity(0.1) : Color.clear)
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(active ? appAccent : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                if vm.collected.isEmpty {
                    Text(tr("把文件或文件夹拖到这里,攒够了再一次性清理",
                            "Drag files or folders here, then clean them all up at once"))
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
                    Button(tr("清空", "Clear")) { vm.clearCollector() }
                        .disabled(vm.collected.isEmpty)
                    Button(role: .destructive) {
                        vm.confirmTrashCollected = true
                    } label: {
                        Label(tr("移到废纸篓", "Move to Trash"), systemImage: "trash")
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
            Text(n.displayName).lineLimit(1).frame(maxWidth: 140)
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
                        let gap = Prefs.theme.bg
                        for s in vm.segments {
                            if s.a0 >= limit { continue }
                            var clipped = s
                            clipped.a1 = min(s.a1, limit)
                            let path = g.path(for: clipped)
                            let isHover = vm.hovered === s.node
                            let fillColor = segmentColor(s, hovered: isHover)
                            ctx.fill(path, with: .color(fillColor))
                            ctx.stroke(path, with: .color(gap), lineWidth: 1)
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
            if vm.viewMode == .types {
                if vm.typeGrouping == .category {
                    TypeLegend(vm: vm, node: current)
                } else {
                    ExtHighlightChip(vm: vm)
                }
            }
        }
    }

    /// 扇形颜色:文件夹模式按文件夹着色;文件类型模式按类别 / 所选扩展名着色
    private func segmentColor(_ s: Segment, hovered: Bool) -> Color {
        guard vm.viewMode == .types else { return SunburstLayout.color(s, hovered: hovered) }
        switch vm.typeGrouping {
        case .category:
            return SunburstLayout.typeColor(s, hovered: hovered, selected: vm.selectedCategory)
        case .byExtension:
            if vm.selectedExt != nil {
                return SunburstLayout.extColor(s, hovered: hovered,
                                               bytes: vm.extHighlight[s.node.id] ?? 0,
                                               color: vm.extHighlightColor)
            }
            return SunburstLayout.typeColor(s, hovered: hovered, selected: nil)
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
            Text(shown.displayName)
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
