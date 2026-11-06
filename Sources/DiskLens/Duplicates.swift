import SwiftUI
import AppKit
import CryptoKit

// 重复文件查找:按大小分组 → 对首尾 64KB 做快速哈希 → 对剩下的做完整 SHA-256。
// 只读文件,不会修改任何东西;删除仍然走收集器 → 废纸篓。

enum DupState { case idle, running, done }

struct DupFile: Identifiable, Sendable {
    let url: URL
    let mod: Date?
    var id: String { url.path }
}

struct DupGroup: Identifiable, Sendable {
    let id = UUID()
    let size: Int64
    var files: [DupFile]
    /// 删到只剩一份能释放的空间
    var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
}

/// 一次查找任务:线程安全地保存进度文字和取消标记
final class DupJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledFlag = false
    private var text = ""

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledFlag }
    func cancel() { lock.lock(); cancelledFlag = true; lock.unlock() }
    var status: String { lock.lock(); defer { lock.unlock() }; return text }
    func set(_ s: String) { lock.lock(); text = s; lock.unlock() }
}

enum DupFinder {
    private static let skipNames: Set<String> = [".git", "node_modules", ".Trash", ".Spotlight-V100", ".fseventsd",
                                                  ".nofollow", ".resolve", ".vol"]

    static func find(root: URL, minSize: Int64, job: DupJob) -> [DupGroup] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
                                      .fileSizeKey, .contentModificationDateKey]
        let libraryPath = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").standardizedFileURL.path

        // 1. 列出文件,按大小分组(跳过 .app 等包内部、.git、node_modules、~/Library)
        job.set(tr("正在列出文件…", "Listing files…"))
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                     options: [.skipsPackageDescendants],
                                     errorHandler: { _, _ in true }) else { return [] }
        var bySize: [Int64: [DupFile]] = [:]
        var seen = 0
        let keySet = Set(keys)
        var finished = false
        while !finished {
            // 每个条目一个自动释放池:否则整个遍历期间的临时对象都不会释放
            autoreleasepool {
                guard let obj = en.nextObject() else { finished = true; return }
                if job.isCancelled { finished = true; return }
                guard let u = obj as? URL, let v = try? u.resourceValues(forKeys: keySet) else { return }
                if v.isSymbolicLink == true { return }
                if v.isDirectory == true {
                    if skipNames.contains(u.lastPathComponent) || u.standardizedFileURL.path == libraryPath {
                        en.skipDescendants()
                    }
                    return
                }
                guard v.isRegularFile == true, let sz = v.fileSize, Int64(sz) >= minSize else { return }
                bySize[Int64(sz), default: []].append(DupFile(url: u, mod: v.contentModificationDate))
                seen += 1
                if seen % 200 == 0 {
                    job.set(tr("正在列出文件… 已找到 \(seen) 个候选", "Listing files… \(seen) candidates"))
                }
            }
        }
        if job.isCancelled { return [] }

        // 2. 只保留大小相同的组;硬链接(同一个 inode)不算重复,因为不占额外空间
        var candidates: [(Int64, [DupFile])] = []
        for (size, files) in bySize where files.count >= 2 {
            var ids = Set<String>()
            var uniq: [DupFile] = []
            for f in files {
                let a = try? fm.attributesOfItem(atPath: f.url.path)
                let id = "\(a?[.systemNumber] ?? 0)-\(a?[.systemFileNumber] ?? 0)"
                if ids.insert(id).inserted { uniq.append(f) }
            }
            if uniq.count >= 2 { candidates.append((size, uniq)) }
        }
        if job.isCancelled { return [] }

        // 3. 快速哈希(首尾 64KB),4. 完整哈希
        let partial = regroup(candidates, partial: true,
                              label: tr("快速比对", "Quick compare"), job: job)
        if job.isCancelled { return [] }
        let full = regroup(partial, partial: false,
                           label: tr("完整比对", "Full compare"), job: job)
        if job.isCancelled { return [] }

        return full
            .map { DupGroup(size: $0.0, files: $0.1.sorted { $0.url.path < $1.url.path }) }
            .sorted { $0.wasted > $1.wasted }
    }

    /// 对每个文件算哈希,把哈希相同的重新分成组(不足两个的丢弃)
    private static func regroup(_ groups: [(Int64, [DupFile])], partial: Bool,
                                label: String, job: DupJob) -> [(Int64, [DupFile])] {
        var flat: [(gi: Int, fi: Int)] = []
        for (gi, g) in groups.enumerated() {
            for fi in g.1.indices { flat.append((gi, fi)) }
        }
        var hashes = [String?](repeating: nil, count: flat.count)
        let lock = NSLock()
        var done = 0

        DispatchQueue.concurrentPerform(iterations: flat.count) { i in
            if job.isCancelled { return }
            let f = groups[flat[i].gi].1[flat[i].fi]
            let h = hash(url: f.url, size: groups[flat[i].gi].0, partial: partial, job: job)
            lock.lock()
            hashes[i] = h
            done += 1
            let d = done
            lock.unlock()
            if d % 10 == 0 { job.set("\(label) \(d)/\(flat.count)") }
        }
        if job.isCancelled { return [] }

        var out: [(Int64, [DupFile])] = []
        var idx = 0
        for g in groups {
            var byHash: [String: [DupFile]] = [:]
            for f in g.1 {
                if let h = hashes[idx] { byHash[h, default: []].append(f) }
                idx += 1
            }
            for (_, fs) in byHash where fs.count >= 2 { out.append((g.0, fs)) }
        }
        return out
    }

    private static func hash(url: URL, size: Int64, partial: Bool, job: DupJob) -> String? {
        autoreleasepool { hashFile(url: url, size: size, partial: partial, job: job) }
    }

    private static func hashFile(url: URL, size: Int64, partial: Bool, job: DupJob) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        // 只读一遍的文件不要塞满系统文件缓存,否则会把其他程序用的缓存挤出去
        _ = fcntl(h.fileDescriptor, F_NOCACHE, 1)
        var hasher = SHA256()
        if partial {
            let part = 64 * 1024
            if let d = try? h.read(upToCount: part) { hasher.update(data: d) }
            if size > Int64(part * 2) {
                try? h.seek(toOffset: UInt64(size) - UInt64(part))
                if let d = try? h.read(upToCount: part) { hasher.update(data: d) }
            }
        } else {
            while !job.isCancelled {
                let more: Bool = autoreleasepool {
                    guard let d = try? h.read(upToCount: 1 << 20), !d.isEmpty else { return false }
                    hasher.update(data: d)
                    return true
                }
                if !more { break }
            }
            if job.isCancelled { return nil }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ViewModel 扩展

extension ViewModel {
    func startDuplicateSearch() {
        guard dupState != .running, let folder = current?.url else { return }
        let job = DupJob()
        dupJob = job
        dupState = .running
        dupStopped = false
        dupGroups = []
        dupScope = folder
        dupStatus = tr("正在准备…", "Preparing…")
        let minSize = Int64(dupMinSizeMB) * 1024 * 1024

        dupTimer?.invalidate()
        dupTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak job] _ in
            guard let job else { return }
            let s = job.status
            Task { @MainActor in self?.dupStatus = s }
        }
        dupTimer?.tolerance = 0.1

        Task.detached(priority: .utility) { [weak self] in
            let groups = DupFinder.find(root: folder, minSize: minSize, job: job)
            await MainActor.run {
                guard let self, self.dupJob === job else { return }
                self.dupTimer?.invalidate()
                self.dupGroups = groups
                self.dupStopped = job.isCancelled
                self.dupState = .done
            }
        }
    }

    func stopDuplicateSearch() {
        guard dupState == .running else { return }
        dupJob?.cancel()
        dupStatus = tr("正在停止…", "Stopping…")
    }

    /// 清理之后,去掉已经不存在的文件,剩不到两份的组也去掉
    func pruneDuplicates() {
        let fm = FileManager.default
        dupGroups = dupGroups.compactMap { g in
            var g = g
            g.files = g.files.filter { fm.fileExists(atPath: $0.url.path) }
            return g.files.count >= 2 ? g : nil
        }
    }

    func dupNode(_ f: DupFile, size: Int64) -> Node {
        Node(url: f.url, name: f.url.lastPathComponent, isDir: false, size: size)
    }

    /// 同一组里还没被收集的份数
    private func uncollectedCount(_ g: DupGroup) -> Int {
        g.files.filter { !isCollected(dupNode($0, size: g.size)) }.count
    }

    /// 永远至少留一份:只要收集这份会把整组都收集光,就不允许
    func canCollect(_ f: DupFile, in g: DupGroup) -> Bool {
        !isCollected(dupNode(f, size: g.size)) && uncollectedCount(g) > 1
    }

    /// 保留这一份,其余加入收集器
    func keepOnly(_ f: DupFile, in g: DupGroup) {
        for other in g.files where other.id != f.id {
            collect(dupNode(other, size: g.size))
        }
    }

    /// 每组保留修改时间最早的一份,其余全部加入收集器
    func collectDuplicatesKeepingOldest() {
        for g in dupGroups {
            let sorted = g.files.sorted {
                ($0.mod ?? .distantFuture, $0.url.path) < ($1.mod ?? .distantFuture, $1.url.path)
            }
            for f in sorted.dropFirst() { collect(dupNode(f, size: g.size)) }
        }
    }
}

// MARK: - 列表

struct DupListView: View {
    @ObservedObject var vm: ViewModel

    private var totalWasted: Int64 { vm.dupGroups.reduce(0) { $0 + $1.wasted } }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            switch vm.dupState {
            case .idle:
                Text(tr("选择最小文件大小,然后点「开始查找」。\n\n只读取文件内容来比对,不会修改任何文件。为安全起见,不包含应用包内部、.git、node_modules 和 ~/Library。硬链接不算重复。",
                        "Pick a minimum file size, then click Find Duplicates.\n\nFiles are only read for comparison, never modified. For safety, app bundles, .git, node_modules and ~/Library are skipped. Hard links are not counted as duplicates."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .running:
                VStack(spacing: 10) {
                    ProgressView()
                    Text(vm.dupStatus)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                results
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(tr("查找范围:\(vm.current?.displayName ?? "-")", "Scope: \(vm.current?.displayName ?? "-")"))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Text(tr("最小文件", "Min size")).font(.callout)
                Picker("", selection: $vm.dupMinSizeMB) {
                    Text("1 MB").tag(1)
                    Text("10 MB").tag(10)
                    Text("100 MB").tag(100)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(vm.dupState == .running)
                Spacer()
                if vm.dupState == .running {
                    Button(role: .destructive) {
                        vm.stopDuplicateSearch()
                    } label: {
                        Label(tr("停止", "Stop"), systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        vm.startDuplicateSearch()
                    } label: {
                        Label(vm.dupState == .done ? tr("重新查找", "Search Again") : tr("开始查找", "Find Duplicates"),
                              systemImage: "doc.on.doc")
                    }
                    .disabled(vm.current == nil)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var results: some View {
        if vm.dupGroups.isEmpty {
            Text(vm.dupStopped
                 ? tr("已停止,还没有发现重复文件。", "Stopped; no duplicates found yet.")
                 : tr("没有发现重复文件。", "No duplicate files found."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("\(vm.dupGroups.count) 组重复,删到每组只剩一份可释放",
                            "\(vm.dupGroups.count) duplicate group\(vm.dupGroups.count == 1 ? "" : "s"); keeping one of each frees"))
                        .font(.callout)
                    Spacer()
                    Text(formatSize(totalWasted)).font(.headline.monospacedDigit())
                }
                if vm.dupStopped {
                    Text(tr("查找被中途停止,结果不完整。", "The search was stopped early, so results are incomplete."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    vm.collectDuplicatesKeepingOldest()
                } label: {
                    Label(tr("每组保留最早的一份,其余加入收集器",
                             "Keep the oldest of each; add the rest to Collector"),
                          systemImage: "tray.and.arrow.down")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.dupGroups) { g in
                        DupGroupView(vm: vm, group: g)
                        Divider()
                    }
                }
            }
        }
    }
}

struct DupGroupView: View {
    @ObservedObject var vm: ViewModel
    let group: DupGroup
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 12)
                    Text(group.files.first?.url.lastPathComponent ?? "")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("× \(group.files.count)").foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(tr("可释放 \(formatSize(group.wasted))", "frees \(formatSize(group.wasted))"))
                            .font(.callout.monospacedDigit())
                        Text(tr("每份 \(formatSize(group.size))", "\(formatSize(group.size)) each"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(group.files) { f in fileRow(f) }
            }
        }
    }

    private func fileRow(_ f: DupFile) -> some View {
        let node = vm.dupNode(f, size: group.size)
        let dir = (f.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        return HStack(spacing: 8) {
            Image(systemName: vm.isCollected(node) ? "tray.full.fill" : "doc")
                .foregroundStyle(vm.isCollected(node) ? appAccent : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(dir)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.head)
                if let m = f.mod {
                    Text(tr("修改于 \(formatDate(m))", "Modified \(formatDate(m))"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button { vm.reveal(node) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(tr("在 Finder 中显示", "Reveal in Finder"))
            Button { vm.keepOnly(f, in: group) } label: { Image(systemName: "checkmark.circle") }
                .buttonStyle(.borderless)
                .help(tr("保留这一份,其余加入收集器", "Keep this one; add the others to Collector"))
            Button { vm.collect(node) } label: { Image(systemName: "tray.and.arrow.down") }
                .buttonStyle(.borderless)
                .disabled(!vm.canCollect(f, in: group))
                .help(tr("加入收集器(每组至少保留一份)", "Add to Collector (at least one copy always stays)"))
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .help(f.url.path)
    }
}
