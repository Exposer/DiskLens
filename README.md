# DiskLens

**English** | [中文](#中文)

A native macOS disk-usage analyzer built with SwiftUI. See at a glance what is eating your disk, drill into folders on an interactive sunburst chart, and clean up in one go.

## Features

- **Sunburst chart** – up to 4 rings, click a slice to drill in, click the center to go back up, hover to see name and size. Breadcrumbs for quick navigation.
- **Fast scanning** – top-level folders are scanned in parallel on all CPU cores. Small items (< 2 MB) are merged into a single node to keep memory low.
- **Scan animation** – a live animated ring with running byte count and the directory currently being scanned; the chart sweeps open when the scan finishes.
- **Collector** – drag slices or list rows into the collector tray at the bottom, review the total size, then move everything to the Trash at once. Nested selections are merged automatically so nothing is counted twice.
- **File type breakdown** – switch the side panel to *File Types* to see video, audio, images, documents, archives/installers/disk images, apps, code and other, with a stacked overview bar. Click a type to list its largest files.
- **Color by type** – in *File Types* mode the chart is colored by dominant file type; pick a type in the legend to highlight where it lives and fade out everything else.
- **Purgeable space** – the bottom bar splits the startup volume into *used*, *purgeable* and *free*, so you can tell what macOS can reclaim by itself.
- **Safe deletion** – items are moved to the Trash (never permanently deleted) after a confirmation, so they can be restored.
- **Private** – everything runs locally. No network access, no telemetry.

## Requirements

- macOS 13 (Ventura) or later
- Xcode or the Command Line Tools (`xcode-select --install`) with Swift 5.9+

## Build & Run

```bash
git clone https://github.com/Exposer/DiskLens.git
cd DiskLens
```

Run directly:

```bash
swift run -c release
```

Or build a double-clickable app bundle (with icon, ad-hoc signed):

```bash
./make_app.sh
```

This produces `DiskLens.app`; drag it into `/Applications`. You can also open `Package.swift` in Xcode and press ⌘R.

> **Gatekeeper:** the app is only ad-hoc signed. If macOS blocks it, right-click the app and choose *Open*.

## Permissions

To scan protected locations such as `~/Library`, grant **Full Disk Access** in *System Settings → Privacy & Security → Full Disk Access* (a shortcut button is in the app's status bar). Without it, some folders are skipped and totals will be lower.

## Notes

- Sizes are allocated sizes on disk, so they may differ slightly from Finder's "logical" sizes.
- Purgeable content (caches, local snapshots, re-downloadable iCloud files) is not visible to a file scan, so scanned totals can be lower than the "used" figure.
- Symbolic links are skipped. When scanning `/`, `/Volumes` and `/System/Volumes` are skipped to avoid counting the same data twice.

## Project layout

```
Sources/DiskLens/
├── App.swift          App entry point
├── Model.swift        Scanner, data model, sunburst layout, view model
├── Views.swift        Main window, file list, collector, sunburst view
├── Categories.swift   File type classification, type coloring, legend
└── Capacity.swift     Used / purgeable / free volume bar
Resources/AppIcon.png  1024×1024 app icon source
make_app.sh            Builds DiskLens.app
```

## License

[MIT](LICENSE)

---

<a id="中文"></a>

# DiskLens(中文)

[English](#disklens) | **中文**

一款用 SwiftUI 编写的原生 macOS 磁盘空间分析工具。一眼看出是什么占满了你的磁盘,在交互式环形图里逐层深入,再一次性清理。

## 功能

- **环形图(Sunburst)**:最多 4 圈。点击扇形进入该目录,点击中心返回上一级,悬停显示名称和大小,顶部有面包屑导航。
- **快速扫描**:第一层目录在所有 CPU 核心上并行扫描。小于 2 MB 的项目合并成一个节点,节省内存。
- **扫描动画**:扫描时显示旋转的动态圆环、已统计的大小和当前正在扫描的目录;扫描完成后环形图会顺时针展开。
- **收集器**:把环形图扇形或列表行拖到底部的收集器里,查看总大小,然后一次性移到废纸篓。重叠的选择会自动合并,不会重复计算。
- **按文件类型汇总**:把侧边栏切到「文件类型」,可以看到视频、音频、图片、文档、压缩包/安装包/磁盘映像、应用程序、代码和其他的占比,并带一条堆叠总览条。点某个类型,列出该类型里最大的文件。
- **按类型着色**:在「文件类型」模式下,环形图按主要文件类型着色;在图例里选一个类型,就能高亮它分布在哪里,其余部分变淡。
- **可清除空间**:底部容量条把启动磁盘分成「已用」「可清除」「空闲」三段,让你知道哪些空间 macOS 会自动回收。
- **安全删除**:确认后只会移到废纸篓,不会永久删除,可以随时恢复。
- **隐私**:全部在本地运行,不联网,没有任何数据上报。

## 系统要求

- macOS 13(Ventura)或更高版本
- Xcode 或命令行工具(`xcode-select --install`),Swift 5.9+

## 编译与运行

```bash
git clone https://github.com/Exposer/DiskLens.git
cd DiskLens
```

直接运行:

```bash
swift run -c release
```

或者打包成可双击的 App(带图标,自签名):

```bash
./make_app.sh
```

会生成 `DiskLens.app`,把它拖进「应用程序」即可。也可以用 Xcode 打开 `Package.swift`,然后按 ⌘R。

> **Gatekeeper**:App 只做了本地自签名。如果被 macOS 拦截,右键点击 App 选择「打开」。

## 权限

要扫描 `~/Library` 等受保护的位置,请在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权(App 状态栏里有直达按钮)。没有授权的话,部分文件夹会被跳过,统计结果会偏小。

## 说明

- 统计的是文件在磁盘上实际占用的空间,和访达显示的「逻辑大小」可能略有差异。
- 可清除内容(缓存、本地快照、可重新下载的 iCloud 文件)文件扫描看不到,所以扫描总和可能小于「已用」。
- 符号链接会被跳过。扫描 `/` 时会跳过 `/Volumes` 和 `/System/Volumes`,避免同一份数据被重复统计。

## 项目结构

```
Sources/DiskLens/
├── App.swift          应用入口
├── Model.swift        扫描器、数据模型、环形图布局、ViewModel
├── Views.swift        主窗口、文件列表、收集器、环形图
├── Categories.swift   文件类型分类、按类型着色、图例
└── Capacity.swift     已用 / 可清除 / 空闲 容量条
Resources/AppIcon.png  1024×1024 应用图标源文件
make_app.sh            打包 DiskLens.app
```

## 许可证

[MIT](LICENSE)
