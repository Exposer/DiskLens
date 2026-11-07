**English** | [中文](#中文)

# DiskLens 1.1

A reliability release: it fixes a crash-prone scanner race, makes the duplicate finder and Trash cleanup safer and more consistent, and warns you when a scan couldn't read some folders. No new views or settings.

## Fixed

- **Scan could crash or lose a folder** – the scanner wrote its top-level results from two threads without a lock; on a disk or home folder with many files next to folders it could crash or leave a top-level folder out (a total that is too small).
- **Duplicates: all copies could end up in the Trash** – "Keep the oldest of each" and "Keep only this one" now always leave one copy per group, even if some copies were already in the Collector.
- **Duplicate search follows the scanner's rules** – from `/` it no longer walks into other volumes (external or network drives, disk images), `/Volumes` or cloud-sync folders; inside `~/Library` it now really skips it, as the screen says.
- **Hard links are counted once** – pnpm store, Homebrew, git objects and the like used to be counted once per name, so totals and the "safe to clean" sizes in Space hogs could exceed the space really used. The other names still show, with size 0.
- **After moving things to the Trash, the results stay consistent** – the By-extension view, the saved scan and reports no longer count trashed bytes; trashing a 1–2 MB duplicate lowers the folder totals; and if the folder you were viewing is trashed you are taken back to the nearest folder that still exists.
- **Compare window** – quickly switching between earlier scans could show one date with another scan's numbers, and trashing files during a comparison could corrupt it.
- **CSV export** – files named like `=HYPERLINK(...)` are no longer run as formulas by Excel / Numbers.

## Added

- **Permission warning after a scan** – if some folders couldn't be read (usually missing Full Disk Access), a banner says how many, with buttons to open the settings and to rescan. Before, they silently counted as 0 bytes.

## Changed

- Less freezing after a cleanup (the saved scan is written once, after you stop trashing); smoother scrolling and hovering in file lists.

## Install

A prebuilt `DiskLens-1.1-macos-arm64.zip` (Apple Silicon, macOS 13+) is attached. Unzip it and drag `DiskLens.app` into `/Applications`. It is signed with a personal Apple Development certificate and **not notarized**, so on other Macs macOS may block it: right-click the app and choose *Open*. To scan protected locations such as `~/Library`, grant **Full Disk Access** in *System Settings → Privacy & Security → Full Disk Access*.

You can also build from source: `git clone https://github.com/Exposer/DiskLens.git && cd DiskLens && ./make_app.sh`. See the [README](https://github.com/Exposer/DiskLens#readme) and the full [CHANGELOG](https://github.com/Exposer/DiskLens/blob/v1.1/CHANGELOG.md).

---

<a id="中文"></a>

[English](#disklens-11) | **中文**

# DiskLens 1.1(中文)

这是一个以稳定性为主的版本:修复了可能导致崩溃的扫描竞态,让重复文件查找和移到废纸篓更安全、结果更一致,并在扫描有目录读不了时给出提示。没有新增视图或设置。

## 修复

- **扫描可能崩溃或丢掉文件夹**:扫描器在两个线程里同时写顶层结果却没有加锁;扫描整盘或主目录(顶层既有很多文件又有文件夹)时可能崩溃,或漏掉某个顶层文件夹,使总大小偏小。
- **重复文件:可能把整组副本都移进废纸篓**:「每组保留最早的一份」和「只保留这一份」现在始终每组至少留一份,即使其中有些副本已经在收集器里。
- **重复文件查找遵循和扫描器相同的规则**:从 `/` 查找时不再进入其它卷(外接盘、网络盘、磁盘映像)、`/Volumes` 和云盘目录;在 `~/Library` 里面查找时也会真正跳过,和界面上写的一致。
- **硬链接只算一次**:pnpm store、Homebrew、git 对象等以前每个名字都算一遍,总数和「占用大户」里「可安全清理」的大小可能比真实占用还大。其余的名字仍会显示,大小为 0。
- **移到废纸篓后结果保持一致**:「按扩展名」视图、已保存的扫描结果和报告不再统计已删除的字节;删除 1~2 MB 的重复文件后所在文件夹的总大小会相应减少;正在查看的文件夹被移进废纸篓时,会自动回到最近一个还存在的文件夹。
- **对比窗口**:快速切换历史扫描时可能显示一个日期却配着另一次扫描的数字;对比期间把文件移进废纸篓还可能让计算出错。
- **CSV 导出**:名字像 `=HYPERLINK(...)` 的文件不再会被 Excel / Numbers 当成公式执行。

## 新增

- **扫描后的权限警告**:如果有目录没能读取(通常是没有「完全磁盘访问权限」),会弹出提示条说明有多少个,并提供「打开设置」和「重新扫描」按钮。以前这些目录会被悄悄算成 0 字节。

## 变更

- 清理后不再那么卡(已保存的扫描结果在你停止清理之后只写一次);文件列表滚动和悬停更流畅。

## 安装

附带了预编译的 `DiskLens-1.1-macos-arm64.zip`(Apple Silicon,macOS 13 及以上)。解压后把 `DiskLens.app` 拖进「应用程序」即可。它用个人的 Apple Development 证书签名,**没有公证**,所以在其它 Mac 上可能被系统拦截:右键点击应用,选择「打开」。要扫描 `~/Library` 等受保护的位置,请在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权。

也可以从源码编译:`git clone https://github.com/Exposer/DiskLens.git && cd DiskLens && ./make_app.sh`。详见 [README](https://github.com/Exposer/DiskLens#readme) 和完整的 [CHANGELOG](https://github.com/Exposer/DiskLens/blob/v1.1/CHANGELOG.md)。
