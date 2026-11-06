# Changelog / 更新日志

All notable changes to DiskLens are recorded here. Each entry is written in English and Chinese.
DiskLens 的所有重要改动都记录在这里,每条中英文对照。

Format follows [Keep a Changelog](https://keepachangelog.com/). Versions `0.1.0`–`0.10.0` correspond to the source packages v1–v10 delivered during development.
格式参考 [Keep a Changelog](https://keepachangelog.com/)。`0.1.0`–`0.10.0` 对应开发过程中交付的 v1–v10 源码包。

## [Unreleased]

## [0.18.0] - 2026-11-06

### Added / 新增
- **Compare scans** (new *Compare* button in the toolbar): compares the scan you are looking at with an earlier one to show what grew or shrank. The window shows the total change, the time span, and how many large files are new or removed; a *Folder hierarchy* tab lets you drill from the biggest changes down to the exact folder (red = grew, green = shrank, with an *Other (small items)* row for the rest), and an *Individual files* tab lists files that grew, are new, shrank or were removed, with Collector and Reveal in Finder buttons. / **对比扫描**(工具栏新增「对比」按钮):把当前查看的扫描和之前的某次扫描对比,看磁盘是被什么撑大或腾出来的。窗口显示总大小变化、时间跨度、新增和删除的大文件个数;「文件夹层级」页可以从变化最大的地方逐层点进去找到具体文件夹(红色 = 变大,绿色 = 变小,其余汇总在「其他(小文件等)」);「单个文件」页列出增长、新增、减少、已删除的文件,可加入收集器或在 Finder 中显示。
- **Scan history**: every complete scan now also saves a snapshot, keeping the latest 8 per folder. The previous "latest result" is folded into the history the first time, so you can compare right after your next scan. / **扫描历史**:每次完整扫描都会另存一份快照,每个文件夹保留最近 8 份。第一次保存历史时,会把之前的「最新结果」也并进去,所以下次扫描完就能马上对比。

### Changed / 变更
- Moving items to the Trash only updates the latest saved result, not the history, so history snapshots stay exactly as they were scanned. / 移到废纸篓后只更新「最新结果」,不改历史快照,历史快照始终保持扫描时的样子。
- *Clear Cache* now also removes the history snapshots, and its size includes them. / 「清除缓存」现在也会清掉历史快照,显示的大小也包含它们。

## [0.17.0] - 2026-11-06

### Added / 新增
- **Exact extension totals for the scan root**: while scanning, DiskLens now records the exact size and file count of every extension across *all* files, including the small ones that are merged in the tree (e.g. hundreds of thousands of `.js` files in `node_modules`). On the scan root, *Types → By extension* shows these exact numbers; inside a subfolder it still uses the ≥ 2 MB approximation, with a note saying so. / **扫描根目录的精确扩展名总表**:扫描时记录**所有**文件(包括树里被合并掉的小文件,比如 `node_modules` 里几十万个 `.js`)按扩展名的精确大小和文件数。在扫描根目录上,「文件类型 → 按扩展名」显示这份精确数据;进到子文件夹后仍用 ≥ 2 MB 的近似统计,并有文字说明。
- The exact table is saved with the scan result, and the Markdown report uses it (with a note when it isn't available). / 精确总表随扫描结果一起保存;Markdown 报告也使用它(没有时会注明)。

### Changed / 变更
- Scan results saved by the previous version can still be loaded; they just don't have the exact table until you rescan. / 上一版保存的扫描结果仍然可以载入,只是在重新扫描之前没有精确总表。

## [0.16.0] - 2026-11-06

### Added / 新增
- **Sunburst highlights the selected extension**: after you click an extension on the *Types → By extension* list, the chart fades everything else and lights up the slices that contain it — the more of that extension a folder holds, the stronger its color. A pill below the chart shows what is highlighted (file count and size) and clears it with ✕. / **环形图高亮所选扩展名**:在「文件类型 → 按扩展名」里点一个扩展名后,图表会淡化其余部分,只点亮包含它的扇形,文件夹里这种文件越多颜色越鲜艳。图表下方的提示条显示正在高亮什么(文件数和大小),点 ✕ 取消。

### Changed / 变更
- In *By extension* mode the chart no longer shows the category legend (it only applies to *By category*) and no longer reuses a stale category highlight. / 「按扩展名」模式下,图表不再显示类别图例,也不会沿用之前选过的类别高亮。

## [0.15.0] - 2026-11-06

### Added / 新增
- **Usage by file extension**: the *Types* tab now has a *By category / By extension* switch. *By extension* ranks every extension (`.mp4`, `.dmg`, `.swift`, …) by total size with file count, percentage and a bar, plus a filter box. Click an extension to list its 200 largest files, with the usual Collector / Reveal / Trash actions. / **按扩展名统计占用**:「文件类型」页新增「按类别 / 按扩展名」切换。「按扩展名」按总大小排列所有扩展名(`.mp4`、`.dmg`、`.swift` 等),显示文件数、占比和占比条,带筛选框;点一个扩展名可列出该类型里最大的 200 个文件,同样支持加入收集器、在 Finder 中显示、移到废纸篓。
- Files of 2 MB or more are counted per extension exactly; the smaller files merged during the scan appear as one *Small items* row with their exact total size. / 2 MB 以上的文件按扩展名精确统计;扫描时合并掉的小文件显示成一行「小文件」,总大小是准确的。
- The Markdown report gets a *By Extension (top 20)* table. / Markdown 报告新增「按扩展名(前 20)」表格。

### Fixed / 修复
- After picking a file type on the *Types* tab, switching to *Largest*, *Hogs* or *Dupes* kept showing that type's file list instead of the tab you chose. The side panel now switches strictly by tab. / 在「文件类型」页点进某个类型后,再切到「大文件」「占用大户」「重复文件」,仍然显示那个类型的文件列表而不是所选标签;现在侧边栏严格按标签切换。

## [0.14.0] - 2026-11-06

### Added / 新增
- **Export scan report** (new *Export* menu in the toolbar). *Markdown report*: scanned location and time, disk capacity (used / purgeable / free), breakdown by file type, largest top-level folders and files, the 50 largest files with modified dates, plus Space Hogs, Duplicate Files and Collector contents if you have used those pages. *CSV file list*: every scanned file of 2 MB or more (path, name, size in bytes, size, type, modified time), UTF-8 with BOM so Excel and Numbers show Chinese correctly. / **导出扫描报告**(工具栏新增「导出」菜单)。*Markdown 报告*:扫描位置和时间、磁盘容量(已用 / 可清除 / 空闲)、按文件类型汇总、最大的第一层文件夹和文件、带修改时间的 50 个最大文件,以及你用过的「占用大户」「重复文件」和收集器内容。*CSV 文件清单*:扫描到的所有 2 MB 以上的文件(路径、名称、字节数、大小、类型、修改时间),UTF-8 带 BOM,Excel 和 Numbers 能正确显示中文。
- The report follows the interface language, and your home folder is shown as `~` in paths so a shared report doesn't reveal your user name. / 报告语言跟随界面语言;路径里的个人文件夹显示为 `~`,分享报告时不会暴露用户名。

## [0.13.0] - 2026-11-06

### Added / 新增
- **Find large files you haven't touched in a long time**: the *Largest* tab can now filter to files not modified in 3+ months / 6+ months / 1+ year / 2+ years, and sort by *Oldest first*. Each row shows how long ago the file was modified (orange when over a year; hover for the exact date). / **找出很久没碰过的大文件**:「大文件」页新增按修改时间筛选(超过 3 个月 / 6 个月 / 1 年 / 2 年没修改)和「最久未修改在前」排序;每一行显示文件多久前修改的(超过一年显示成橙色,悬停可看确切日期)。
- The list header shows the number of files and their total size. / 列表顶部显示文件个数和合计大小。

### Changed / 变更
- The scanner now records each file's last-modified time. Saved scan results from earlier versions are ignored once and rescanned automatically. / 扫描时会记录每个文件的最后修改时间。旧版本保存的扫描结果会被忽略一次,并自动重新扫描。

## [0.12.0] - 2026-11-06

### Added / 新增
- **Largest Files leaderboard** (new *Largest* tab): ranks the biggest files in the folder you are viewing, with rank number, file-type icon, relative path, size bar, and per-row Collector / Reveal in Finder / Trash actions. Filter by file type and choose Top 50 / 100 / 200; shows the total of the listed files. It reads the in-memory scan result, so it opens instantly. / **大文件排行榜**(新增「大文件」页):列出当前文件夹里最大的文件,带名次、类型图标、相对路径、大小占比条,每行可加入收集器、在 Finder 中显示或移到废纸篓。可按文件类型筛选,可选前 50 / 100 / 200 个,并显示合计大小。直接使用内存里的扫描结果,打开即显示。

### Changed / 变更
- The side panel is wider by default (440 px, up to 600 px) so five tabs fit; the *Duplicates* tab is labelled *Dupes* in English. / 侧边栏默认更宽(440 px,最宽 600 px),以便放下五个标签;英文里「重复文件」标签缩写为 *Dupes*。
- The leaderboard refreshes automatically after items are moved to the Trash. / 移到废纸篓后,排行榜会自动刷新。

## [0.11.0] - 2026-11-06

### Added / 新增
- **Duplicate file finder** (new *Duplicates* tab): searches the folder you are viewing for identical files with a minimum size of 1 / 10 / 100 MB. It groups by size, quick-hashes the first and last 64 KB, then confirms with a full SHA-256, using all CPU cores; it can be stopped at any time. Hard links are not counted as duplicates, and app bundles, `.git`, `node_modules` and `~/Library` are skipped for safety. / **重复文件查找**(新增「重复文件」页):在当前查看的文件夹里查找内容完全相同的文件,最小大小可选 1 / 10 / 100 MB。先按大小分组,再对首尾 64 KB 做快速哈希,最后用完整 SHA-256 确认,多核并行,可随时停止。硬链接不算重复;为安全起见,不包含应用包内部、`.git`、`node_modules` 和 `~/Library`。
- Per group: expand to see every copy's folder and modified date; reveal in Finder; *Keep this one* (adds all the others to the Collector); add a single copy to the Collector. At least one copy of each group is always kept. / 每组可展开查看每份的所在文件夹和修改时间,支持在 Finder 中显示、「保留这一份」(其余全部加入收集器)、单独加入收集器;每组始终至少保留一份。
- *Keep the oldest of each* – one click adds every group's extra copies to the Collector. / 「每组保留最早的一份」:一键把每组多出来的副本都加入收集器。
- `CHANGELOG.md`, plus a contributor rule (`CLAUDE.md`) and a pre-commit hook (`.githooks/pre-commit`) so every code change must come with a changelog entry. / 新增更新日志,以及约定文件 `CLAUDE.md` 和提交前检查脚本,保证每次改动都要同步写入更新日志。

### Changed / 变更
- The side-panel tab labels are shorter (*Types*, *Hogs*) so four tabs fit. / 侧边栏标签名称缩短(英文 *Types*、*Hogs*),以便放下四个标签。
- After items are moved to the Trash, the duplicate results are refreshed automatically. / 移到废纸篓后,重复文件结果会自动刷新。

### Fixed / 修复
- README project layout now lists every source file. / README 的项目结构补全了所有源文件。

## [0.10.0] - 2026-11-06

### Added / 新增
- **Space Hogs tab** – measures 20 well-known space eaters (Xcode DerivedData / device support / archives / simulators, Homebrew, npm, Yarn, pnpm, CocoaPods, Gradle, pip, Cargo, Docker, caches, logs, iOS backups, Trash, Downloads, Messages attachments, Photos library), labels each *Safe to clean* / *Be careful* / *Info*, shows the recommended cleanup command with a copy button, and can add all safe items to the Collector in one click. / **占用大户页**:统计 20 个常见占空间位置的大小,标注「可清理 / 谨慎 / 仅提示」,显示推荐清理命令(可一键复制),并可一键把所有「可清理」项加入收集器。
- **Stop Scan button** (toolbar and scanning screen). The partial result is shown with an "incomplete" banner and is never saved to the cache. / **停止扫描按钮**(工具栏和扫描画面)。已扫到的部分会显示,并带「结果不完整」横幅,不会保存为缓存。

### Changed / 变更
- The Collector now detects containment by file path, so adding a folder merges any already-collected items inside it. / 收集器改为按文件路径判断包含关系,放入文件夹时会自动合并其中已收集的项目。
- Moving an item that is not part of the scan tree (e.g. a space hog) to the Trash now also removes it from the scan tree and saved cache. / 移动不在扫描树里的项目(如占用大户)到废纸篓时,会同步从扫描树和已保存的缓存里去掉。

## [0.9.0] - 2026-11-06

### Added / 新增
- **English / 中文 interface switch** (🌐 menu in the toolbar). The choice is remembered; the default follows the system language. / **中英文界面切换**(工具栏 🌐 菜单),选择会被记住,默认跟随系统语言。
- **Apple Books-inspired color themes**: Original (follows system), Paper, Calm, Quiet, Night. Backgrounds, accent color and chart colors adapt. / **参考 Apple Books 的配色方案**:原始(跟随系统)、纸张、柔和、安静、夜间,背景、强调色和图表颜色随之变化。
- Switching language or theme rebuilds the UI without losing the scan result or the Collector contents. / 切换语言或配色不会丢失扫描结果和收集器内容。

### Changed / 变更
- App icon: disk centered, smaller magnifier, silver magnifier color (chosen from six options). / 图标:盘片居中,放大镜缩小,放大镜改为银白色(从六个备选中选定)。

## [0.8.0] - 2026-11-06

### Changed / 变更
- **New app icon**: a disk platter with a magnifying glass (replaces the plain sunburst icon). / **新图标**:磁盘盘片加放大镜(取代原来的纯环形图图标)。

## [0.7.0] - 2026-11-06

### Added / 新增
- **Clear Cache button** in the status bar, showing the cache size; asks for confirmation and only deletes DiskLens's own cache files. / 状态栏新增**清除缓存按钮**,显示缓存大小;确认后只删除 DiskLens 自己的缓存文件。

## [0.6.0] - 2026-11-06

### Added / 新增
- **Saved scan results**: every completed scan is stored in `~/Library/Application Support/DiskLens/` and reloaded instantly on launch, with a banner showing when it was scanned and a Rescan button. Trashed items are removed from the saved result too. / **保存扫描结果**:每次完整扫描的结果保存到 `~/Library/Application Support/DiskLens/`,下次启动立即载入,顶部横幅显示扫描时间并提供「重新扫描」;移到废纸篓的项目也会同步从缓存里去掉。
- The last scanned folder is remembered. / 记住上次扫描的文件夹。

## [0.5.0] - 2026-11-06

### Added / 新增
- **Color the sunburst by file type** in File Types mode: slices use their dominant type's color; picking a type in the legend highlights where it lives and fades the rest. / **环形图按文件类型着色**:每个扇形用其主要类型的颜色;在图例里选一个类型会高亮其分布并淡化其余。
- Type legend below the chart. / 环形图下方新增类型图例。
- `README.md` (English + 中文), MIT `LICENSE`, and a README screenshot placeholder. / 新增中英文 `README.md`、MIT 许可证和截图占位图。

## [0.4.0] - 2026-11-06

### Added / 新增
- **File type breakdown**: a *Folders / File Types* switch in the side panel; eight categories (video, audio, images, documents, archives / installers / disk images, apps, code / dev files, other) with a stacked overview bar. / **按文件类型汇总**:侧边栏新增「文件夹 / 文件类型」切换;八个类别(视频、音频、图片、文档、压缩包/安装包/磁盘映像、应用程序、代码/开发文件、其他),带堆叠总览条。
- Click a type to list its 200 largest files (≥ 2 MB), with the same actions as the folder list. / 点击某个类型,列出该类型里最大的 200 个文件(≥ 2 MB),支持和文件夹列表相同的操作。

## [0.3.0] - 2026-11-06

### Added / 新增
- **Purgeable space display**: the status bar splits the startup volume into Used / Purgeable / Free, with an explanatory popover and a shortcut to Storage settings. / **可清除空间显示**:状态栏把启动磁盘分成「已用 / 可清除 / 空闲」,带说明弹窗和「储存空间」设置快捷入口。
- First app icon (colored sunburst). / 第一版应用图标(彩色环形图)。

## [0.2.0] - 2026-11-06

### Added / 新增
- **Scan animation**: rotating colored rings with a live byte count and the directory being scanned. / **扫描动画**:旋转的彩色圆环,实时显示已统计大小和正在扫描的目录。
- **Sunburst reveal animation** when a scan finishes and when drilling into a folder. / 扫描完成和进入子目录时,环形图有**顺时针展开动画**。
- **Collector**: drag slices or list rows into the tray at the bottom (or use the add button / context menu), review the total, then move everything to the Trash at once. / **拖拽收集器**:把环形图扇形或列表行拖进底部托盘(也可用按钮或右键菜单加入),查看总大小后一次性移到废纸篓。

## [0.1.0] - 2026-11-06

### Added / 新增
- Initial release: native SwiftUI macOS disk analyzer. / 首个版本:原生 SwiftUI macOS 磁盘分析工具。
- Interactive **sunburst chart** (4 rings): click to drill in, click the center to go up, hover for name and size, breadcrumb navigation. / 交互式**环形图**(4 圈):点击进入、点中心返回、悬停显示名称和大小、面包屑导航。
- **Parallel scanner**; items under 2 MB are merged into a "Small items" node to save memory. / **并行扫描器**;小于 2 MB 的项目合并成「小文件」节点以节省内存。
- Size-sorted file list with percentage bars; reveal in Finder; move to Trash with confirmation. / 按大小排序、带占比条的文件列表;在 Finder 中显示;确认后移到废纸篓。
- Choose any folder, scan the home folder, or scan the whole disk; volume capacity bar; Full Disk Access shortcut. / 可选任意文件夹、扫描个人文件夹或整个磁盘;磁盘容量条;「完全磁盘访问权限」快捷入口。
- `make_app.sh` to build a signed `DiskLens.app` bundle. / 提供 `make_app.sh` 打包 `DiskLens.app`。

[Unreleased]: https://github.com/Exposer/DiskLens/compare/main...HEAD
