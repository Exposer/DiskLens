# DiskLens — instructions for Claude / 给 Claude 的项目约定

A native macOS (SwiftUI, Swift 5.9, macOS 13+) disk-usage analyzer. Package layout: `Sources/DiskLens/*.swift`, `Resources/AppIcon.png`, `make_app.sh`.

## Changelog rule (mandatory) / 更新日志规则(必须遵守)

**Every change to this repository must be recorded in `CHANGELOG.md` in the same commit.**
**对本仓库的任何改动,都必须在同一次提交里写进 `CHANGELOG.md`。**

- Add the entry under `## [Unreleased]`, in the right group: `Added / 新增`, `Changed / 变更`, `Fixed / 修复`, `Removed / 移除`.
- Write each entry in **English and Chinese** on the same bullet, separated by ` / `, like the existing entries. Describe what the user sees, not the implementation.
- When a batch of work is delivered to the user (a new zip / release), rename `[Unreleased]` to the next version `## [0.x.0] - YYYY-MM-DD` and start a fresh empty `[Unreleased]` section.
- Docs-only or tooling-only changes also get an entry. Don't skip it because a change is small.
- Keep `README.md` feature lists (English and 中文) in sync when a feature is added or removed.

A pre-commit hook enforces this. Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

## Conventions / 代码约定

- **All user-visible strings use `tr("中文", "English")`** (see `Settings.swift`). Never hard-code a single language in the UI.
- Colors come from the theme: `Prefs.theme` (`bg`, `bar`, `accent`), `appAccent`, and `tc(h, s, b)` for chart colors. Don't use fixed system colors for chart or panel backgrounds.
- Moving files always goes to the Trash (`FileManager.trashItem`), after a confirmation. Never delete permanently.
- Scan results are cached in `~/Library/Application Support/DiskLens/`; if the cached data shape changes, invalidate old caches (see `ScanStore.load`).
- The app icon is generated from `Resources/AppIcon.png` (1024×1024) by `make_app.sh`.
- This repo is usually edited from a Linux cloud session without the Swift toolchain, so code can't be compiled there. Say so honestly in replies; the user compiles on their Mac.

## Packaging / 打包

- Always package with the fixed signing certificate, otherwise the ad-hoc signature changes every build and macOS drops the Full Disk Access grant (scans then silently miss protected folders and come out ~90 GB too small). / 打包必须用固定证书签名,否则临时签名每次都变,macOS 会丢掉「完全磁盘访问权限」,扫描会漏掉受保护目录(少算约 90 GB)。

  ```bash
  DISKLENS_SIGN_IDENTITY="BF5109770E1B54A53564AA9CF754B6CA52BDC2FE" ./make_app.sh
  ```

  Use the SHA-1 hash, not the name: the keychain has two certificates with the same name, so signing by name fails with "ambiguous". / 用 SHA-1 哈希而不是名字:钥匙串里有两份同名证书,按名字签名会报 "ambiguous"。
- The build number (`CFBundleVersion`) is the git commit count, so it only changes when you commit. / build 号是 git 提交数,提交后才会变。
- The project lives in an iCloud-synced Documents folder; `make_app.sh` builds in `~/Library/Caches/disklens-build` to keep iCloud from stalling the build. Run it in the background with a timeout. / 项目在 iCloud 同步的 Documents 里;`make_app.sh` 把编译产物放在 `~/Library/Caches/disklens-build`,避免 iCloud 拖慢编译,建议后台运行并加超时。
