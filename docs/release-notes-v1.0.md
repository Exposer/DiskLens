**English** | [中文](#中文)

# DiskLens 1.0

The first public release of **DiskLens**, a native macOS disk-usage analyzer built with SwiftUI. See what is eating your disk, drill into folders, and clean up in one go — everything runs locally, with no network access and no telemetry.

## Highlights

**See where the space goes**
- **Three views** – *Ring* (sunburst), *Squares* (treemap) and an expandable *Tree* list. Click to drill in.
- **Fast scanning** – directories are scanned in parallel at every level; in our tests a full-disk scan of about 420 GB of used space took roughly 15 seconds on an Apple Silicon Mac, with a peak of about 90 MB of memory. A disk-platter scan animation shows the progress, and you can stop a scan at any time.
- **Accurate totals** – no double counting of `/.nofollow` and friends, no crossing file-system boundaries (like `du -x`), APFS-compressed files counted correctly, cloud-synced folders (iCloud Drive, Dropbox, OneDrive…) excluded.
- **File types and extensions** – breakdown by category, or by extension with exact totals for the whole scan; the chart lights up where a type or extension lives.
- **Largest files** – a leaderboard, filterable by type and by *not modified in 3 months / 6 months / 1 year / 2 years* to find big files you no longer use.
- **Space hogs** – measures Xcode DerivedData, Homebrew, npm, Docker, iOS backups and other well-known space eaters, tells you which are safe to clean, and shows the recommended cleanup command.
- **Duplicate finder** – size → quick hash → full SHA-256; at least one copy of each group always stays.

**Clean up safely**
- **Collector** – drag or add items, review the total, then move everything to the Trash at once. Files always go to the Trash after a confirmation; nothing is ever deleted permanently.

**Track changes over time**
- **Saved scans** – the app reopens instantly with your last result.
- **Compare scans** – see what grew or shrank between two scans, down to the folder and file; after each scan a banner tells you how much the total changed since last time.
- **Export reports** – Markdown report or CSV file list.

**Keep an eye on the disk**
- **Purgeable space** shown separately from used and free space.
- **Low disk space alert**, a **menu bar icon** showing your available space, quiet **launch at login**, and an optional **menu bar only** mode that hides the Dock icon. Closing the window only hides it, so monitoring keeps running. Scan memory is released 3 minutes after the window is hidden.

**Polish**
- **English / 中文** interface, and **Apple Books-inspired color themes** (Original, Paper, Calm, Quiet, Night).

## Install

### Download (Apple Silicon)

Download **`DiskLens-1.0-macos-arm64.zip`** from the assets below (a Mac with an Apple Silicon chip, macOS 13 or later), unzip it and drag `DiskLens.app` into `/Applications`.

The app is signed with the author's own certificate and is **not notarized**, so macOS blocks it the first time: right-click the app and choose *Open*, or run:

```bash
xattr -dr com.apple.quarantine /Applications/DiskLens.app
```

Intel Macs need to build from source. SHA-256 of the zip: `SHA256_PLACEHOLDER`

### Build from source

macOS 13 or later, Xcode or the Command Line Tools:

```bash
git clone https://github.com/Exposer/DiskLens.git
cd DiskLens
./make_app.sh
```

This produces `DiskLens.app` — drag it into `/Applications`. To sign with a fixed certificate (so the Full Disk Access permission survives rebuilds), run `DISKLENS_SIGN_IDENTITY="<certificate SHA-1>" ./make_app.sh`. The app is not notarized; if macOS blocks it, right-click it and choose *Open*.

To scan protected locations such as `~/Library`, grant **Full Disk Access** in *System Settings → Privacy & Security → Full Disk Access*.

See the [README](https://github.com/Exposer/DiskLens#readme) for details and the full [CHANGELOG](https://github.com/Exposer/DiskLens/blob/v1.0/CHANGELOG.md).

## Since the last development build (0.23)

- **Much faster scanning** (about 47 s → 14 s for a full-disk scan on the author's Mac) and **much lower memory** while scanning (about 1 GB → 90 MB).
- **Squares and Tree views**, plus a redesigned **disk-read scan animation**.
- **Scanning fixes**: whole-disk scans no longer count everything twice via `/.nofollow`, no longer cross file-system boundaries, and count APFS-compressed files; cloud-synced folders are excluded.
- **Memory is released** 3 minutes after the window is hidden.
- The toolbar adapts to narrow windows; the status bar no longer squeezes into vertical columns.
- `make_app.sh` builds outside iCloud-synced folders, supports a fixed signing identity, and fixes the "detritus not allowed" signing failure; the app shows `1.0 (build N)`.

---

<a id="中文"></a>

[English](#disklens-10) | **中文**

# DiskLens 1.0(中文)

**DiskLens** 的第一个公开版本:一款用 SwiftUI 编写的原生 macOS 磁盘空间分析工具。一眼看出是什么占满了你的磁盘,逐层深入,再一次性清理。全部在本地运行,不联网,没有任何数据上报。

## 亮点

**看清空间去了哪里**
- **三种视图**:「环形图」(Sunburst)、「方块图」(Treemap)和可展开的「树状列表」,点击即可逐层深入。
- **快速扫描**:每一层目录都并行扫描;我们测试中,在 Apple Silicon Mac 上扫描整个磁盘(约 420 GB 已用空间)大约 15 秒,内存峰值约 90 MB。扫描时有磁盘盘片动画显示进度,随时可以停止。
- **统计准确**:不会通过 `/.nofollow` 等入口把数据重复计算,不跨文件系统(和 `du -x` 一样),APFS 压缩文件的大小算得正确,云同步文件夹(iCloud Drive、Dropbox、OneDrive 等)不计入。
- **文件类型和扩展名**:按类别汇总,也可以按扩展名汇总(整个扫描范围的总表是精确的);图表会点亮某个类型或扩展名分布在哪里。
- **大文件排行榜**:可按类型筛选,也可按「超过 3 个月 / 6 个月 / 1 年 / 2 年没修改」筛选,找出不再使用的大文件。
- **占用大户**:统计 Xcode DerivedData、Homebrew、npm、Docker、iOS 备份等常见占空间的位置,标明哪些可以放心清理,并给出推荐的清理命令。
- **重复文件查找**:先比大小,再快速哈希,最后完整 SHA-256 确认;每组始终至少保留一份。

**安全清理**
- **收集器**:拖入或加入项目,查看总大小,再一次性移到废纸篓。文件永远是确认后移到废纸篓,绝不会被永久删除。

**随时间追踪变化**
- **保存扫描结果**:下次打开立即显示上次的结果。
- **对比扫描**:看两次扫描之间什么变大了、什么变小了,一直定位到具体文件夹和文件;每次扫描完成后,顶部会提示总大小比上次多了或少了多少。
- **导出报告**:Markdown 报告或 CSV 文件清单。

**盯着磁盘**
- 把**可清除空间**和已用、空闲空间分开显示。
- **磁盘快满提醒**、显示可用空间的**菜单栏图标**、安静的**开机自动启动**,以及可选的**仅菜单栏模式**(隐藏 Dock 图标)。关闭窗口只是隐藏,监控继续运行。窗口隐藏 3 分钟后会释放扫描占用的内存。

**细节**
- **中英文**界面,以及**参考 Apple Books 的配色方案**(原始、纸张、柔和、安静、夜间)。

## 安装

### 下载(Apple 芯片)

从下面的 Assets 里下载 **`DiskLens-1.0-macos-arm64.zip`**(需要 Apple 芯片的 Mac,macOS 13 或更高版本),解压后把 `DiskLens.app` 拖进「应用程序」。

应用用作者自己的证书签名,**没有经过公证**,所以第一次打开会被 macOS 拦截:右键点击应用选择「打开」,或者运行:

```bash
xattr -dr com.apple.quarantine /Applications/DiskLens.app
```

Intel Mac 需要从源码编译。压缩包的 SHA-256:`SHA256_PLACEHOLDER`

### 从源码编译

需要 macOS 13 或更高版本,以及 Xcode 或命令行工具:

```bash
git clone https://github.com/Exposer/DiskLens.git
cd DiskLens
./make_app.sh
```

会生成 `DiskLens.app`,把它拖进「应用程序」即可。想用固定证书签名(这样重新编译后「完全磁盘访问权限」不会失效),运行 `DISKLENS_SIGN_IDENTITY="<证书 SHA-1>" ./make_app.sh`。应用没有经过公证,如果被 macOS 拦截,右键点击它选择「打开」。

要扫描 `~/Library` 等受保护的位置,请在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」里授权。

详情见 [README](https://github.com/Exposer/DiskLens#readme) 和完整的 [更新日志](https://github.com/Exposer/DiskLens/blob/v1.0/CHANGELOG.md)。

## 相比上一个开发版本(0.23)的变化

- **扫描快得多**(在作者的 Mac 上整盘扫描从约 47 秒降到约 14 秒),扫描时**内存低得多**(从约 1 GB 降到约 90 MB)。
- 新增**方块图和树状列表**视图,以及重新设计的**磁盘读取扫描动画**。
- **扫描修复**:整盘扫描不再通过 `/.nofollow` 重复计算,不再跨文件系统,APFS 压缩文件按实际大小计算;云同步文件夹不计入。
- 窗口隐藏 3 分钟后**释放内存**。
- 工具栏能适应窄窗口;状态栏不再在窄窗口里被挤成竖排。
- `make_app.sh` 改为在 iCloud 同步范围之外编译,支持固定签名证书,并修复了 "detritus not allowed" 的签名失败;应用显示为 `1.0 (build N)`。
