**English** | [中文](#中文)

# DiskLens 1.2

A safety and efficiency release, the result of a full code review. It closes two ways the wrong item could end up headed for the Trash, fixes wrong sizes on non-APFS volumes, and makes the app lighter: the window no longer reads the disk while it redraws, and saved scans take far less space. No new views or workflows.

## Fixed

- **Duplicates: files with different content could be reported as duplicates** – a read error was treated like the end of the file, so two same-sized files that both failed to read got the same hash. A read error, or a file whose size changes during the comparison, now excludes that file. Cloud files that aren't downloaded (iCloud *Optimize Storage*, online-only Dropbox / OneDrive files) are skipped instead of being downloaded just to be compared.
- **Collector: dragging text from another app could add an unrelated item** – the row you last dragged but didn't drop was collected. The Collector now only accepts a row dragged from DiskLens's own list.
- **Items left over from a previous scan can't be collected or trashed** – after a rescan, an item that was still referenced had lost track of its folder and could resolve to a same-named item elsewhere. Such items are now refused with a message asking you to rescan.
- **Wrong sizes on volumes that aren't APFS** – on file systems that don't return every attribute (exFAT external disks, SMB / NFS network volumes) the directory listing was parsed out of alignment, giving garbage types and sizes.
- **"Launch at login" tells you why it failed** – the checkbox used to just flip back. The reason is now shown, with a pointer to adding DiskLens under Login Items by hand.

## Changed

- **The window redraws without touching the disk** – the status bar used to list the cache folder and query the disk's capacity on every redraw (each time the mouse moved over a row, and several times a second during a scan). The capacity figures now refresh about every 15 seconds.
- **Saved scans take far less disk space** – the latest result and the history snapshots (up to 8 per folder) are compressed. Files saved by earlier versions are still read; note that DiskLens 1.1 and earlier can't read scans saved by 1.2 and will simply rescan.
- **Space Hogs is quicker after a cleanup** – only the locations that overlap what you just moved to the Trash are measured again, and a refresh requested while one is running is no longer dropped.
- **The permission warning also shows for saved results** – if some folders couldn't be read when the scan was made, results loaded from the cache say so too.
- **Lists stay sorted by size after a cleanup**, and the Tree list no longer rebuilds its rows every time the mouse moves.
- Scanning, the duplicate search and the Space Hogs measurement no longer slow each other down when they run at the same time.
- **Status colors follow the theme** – warning, "grew" and "shrank" colors are tuned for each color theme.

## For developers

- Unit tests for the pure logic (layouts, Compare, low-space thresholds, CSV export, the cache format): `swift test`.
- `make_app.sh` keeps the previous `DiskLens.app` until the new one is built and signed.

## Install

A prebuilt `DiskLens-1.2-macos-arm64.zip` (Apple Silicon, macOS 13+) is attached. Unzip it and drag `DiskLens.app` into `/Applications`. It is signed with a personal Apple Development certificate and **not notarized**, so on other Macs macOS may block it: right-click the app and choose *Open*. To scan protected locations such as `~/Library`, grant **Full Disk Access** in *System Settings → Privacy & Security → Full Disk Access*.

You can also build from source: `git clone https://github.com/Exposer/DiskLens.git && cd DiskLens && ./make_app.sh`. See the [README](https://github.com/Exposer/DiskLens#readme) and the full [CHANGELOG](https://github.com/Exposer/DiskLens/blob/v1.2/CHANGELOG.md).

---

<a id="中文"></a>

[English](#disklens-12) | **中文**

# DiskLens 1.2(中文)

这是一个以安全和效率为主的版本,来自一次完整的代码评审。它堵上了两种可能把不该删的东西送进废纸篓的情况,修复了非 APFS 卷上大小读错的问题,并让应用更轻:界面重绘时不再读磁盘,保存的扫描结果占用的空间小得多。没有新的视图或流程。

## 修复

- **重复文件:内容不同的文件可能被判成重复**:以前读取出错被当成读到了文件结尾,两个大小相同、都读不出来的文件会得到同样的哈希。现在只要读取出错,或者文件在比对期间大小变了,这个文件就不参与比对。还没下载到本地的云文件(iCloud「优化储存空间」、Dropbox / OneDrive 的在线文件)会被跳过,不再为了比对把它们下载回来。
- **收集器:从别的应用拖文字进来,可能把不相干的项目加进去**:被加进去的是你上一次拖过但没放下的那一行。现在收集器只接受从 DiskLens 自己列表里拖出来的行。
- **上一次扫描遗留的项目不能再被收集或移进废纸篓**:重新扫描后,仍被引用的旧项目已经不知道自己在哪个文件夹里,路径可能被解析成别处的同名项目。现在这类项目会被拒绝,并提示重新扫描。
- **非 APFS 卷上大小读错**:在不返回全部属性的文件系统上(exFAT 外接盘、SMB / NFS 网络卷),目录列表的解析会错位,类型和大小读成垃圾值。
- **「开机时自动启动」失败时会说明原因**:以前只是开关自己弹回去。现在会显示原因,并提示可以到「登录项」里手动添加。

## 变更

- **界面重绘时不再读磁盘**:以前状态栏每重绘一次(鼠标每移过一行、扫描时每秒好几次)都会列一遍缓存目录、查一遍磁盘容量。容量数字现在约每 15 秒刷新一次。
- **保存的扫描结果占用的磁盘空间小得多**:最新结果和历史快照(每个文件夹最多 8 份)压缩后再保存。旧版本保存的文件仍然能读;注意 DiskLens 1.1 及更早的版本读不了 1.2 保存的结果,会直接重新扫描。
- **清理之后「占用大户」更快**:只重新统计和刚移进废纸篓的东西有重叠的位置;统计进行中又来的刷新请求不再被丢掉。
- **从缓存载入的结果也会显示权限提示**:扫描时有目录因权限不足没读到的话,下次从缓存载入也会提醒。
- **清理之后列表仍按大小排序**;树形列表在鼠标移过时不再每次重建所有行。
- 扫描、重复文件查找和占用大户统计同时进行时,不再互相拖慢。
- **状态颜色跟随主题**:警告、「变大」「变小」的颜色针对每个配色方案调过。

## 给开发者

- 为纯逻辑加了单元测试(布局、对比、空间不足阈值、CSV 导出、缓存格式):`swift test`。
- `make_app.sh` 等新包编译、签名都成功后才替换旧的 `DiskLens.app`。

## 安装

附带了预编译的 `DiskLens-1.2-macos-arm64.zip`(Apple Silicon,macOS 13 及以上)。解压后把 `DiskLens.app` 拖进「应用程序」即可。它用个人的 Apple Development 证书签名,**没有公证**,所以在其它 Mac 上可能被系统拦截:右键点击应用,选择「打开」。要扫描 `~/Library` 等受保护的位置,请在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权。

也可以从源码编译:`git clone https://github.com/Exposer/DiskLens.git && cd DiskLens && ./make_app.sh`。详见 [README](https://github.com/Exposer/DiskLens#readme) 和完整的 [CHANGELOG](https://github.com/Exposer/DiskLens/blob/v1.2/CHANGELOG.md)。
