import SwiftUI
import AppKit

// MARK: - 语言

enum Language: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    var label: String { self == .zh ? "中文" : "English" }
    var locale: Locale { Locale(identifier: self == .zh ? "zh_CN" : "en_US") }
}

// MARK: - 配色方案(参考 Apple Books 的阅读主题)

enum AppTheme: String, CaseIterable, Identifiable {
    case original, paper, calm, quiet, night
    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return tr("原始", "Original")
        case .paper: return tr("纸张", "Paper")
        case .calm: return tr("柔和", "Calm")
        case .quiet: return tr("安静", "Quiet")
        case .night: return tr("夜间", "Night")
        }
    }

    var isDark: Bool { self == .quiet || self == .night }

    /// nil = 跟随系统
    var scheme: ColorScheme? {
        switch self {
        case .original: return nil
        default: return isDark ? .dark : .light
        }
    }

    /// 内容区背景
    var bg: Color {
        switch self {
        case .original: return Color(nsColor: .windowBackgroundColor)
        case .paper: return Color(hex: 0xF8F1E3)
        case .calm: return Color(hex: 0xE6D9C3)
        case .quiet: return Color(hex: 0x35383D)
        case .night: return Color(hex: 0x111113)
        }
    }

    /// 工具栏 / 收集器 / 状态栏背景
    var bar: Color {
        switch self {
        case .original: return Color(nsColor: .windowBackgroundColor)
        case .paper: return Color(hex: 0xEFE5CF)
        case .calm: return Color(hex: 0xDACCB3)
        case .quiet: return Color(hex: 0x2B2E32)
        case .night: return Color(hex: 0x1B1B1E)
        }
    }

    /// 强调色(按钮、进度条、高亮)
    var accent: Color {
        switch self {
        case .original: return Color(nsColor: .controlAccentColor)
        case .paper: return Color(hex: 0xB5651D)
        case .calm: return Color(hex: 0x8E5A3C)
        case .quiet: return Color(hex: 0xD9A441)
        case .night: return Color(hex: 0xFF9F0A)
        }
    }

    /// 状态色:警告(橙)、危险 / 增加(红)、正常 / 减少(绿)。
    /// 和主题一起调过,在米色纸张和深色背景上都看得清;「原始」主题仍用跟随系统明暗的系统色
    var warn: Color {
        switch self {
        case .original: return .orange
        case .paper: return Color(hex: 0xB7791F)
        case .calm: return Color(hex: 0xA66A1E)
        case .quiet: return Color(hex: 0xE0A94A)
        case .night: return Color(hex: 0xFFB340)
        }
    }

    var bad: Color {
        switch self {
        case .original: return .red
        case .paper: return Color(hex: 0xB3402F)
        case .calm: return Color(hex: 0xA33A2B)
        case .quiet: return Color(hex: 0xE0705F)
        case .night: return Color(hex: 0xFF6961)
        }
    }

    var good: Color {
        switch self {
        case .original: return .green
        case .paper: return Color(hex: 0x4F7A3A)
        case .calm: return Color(hex: 0x4A6F36)
        case .quiet: return Color(hex: 0x7FB069)
        case .night: return Color(hex: 0x6CCB7A)
        }
    }

    /// 图表颜色的饱和度 / 亮度系数:暖色主题调得更柔和,像印刷的纸页
    var chartSat: Double {
        switch self {
        case .original: return 1.0
        case .paper: return 0.78
        case .calm: return 0.70
        case .quiet: return 0.75
        case .night: return 0.90
        }
    }

    var chartBri: Double {
        switch self {
        case .original: return 1.0
        case .paper: return 0.95
        case .calm: return 0.90
        case .quiet: return 0.92
        case .night: return 0.95
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - 全局偏好(语言 / 配色),保存在 UserDefaults

enum Prefs {
    static var language: Language = {
        if let s = UserDefaults.standard.string(forKey: "language"), let l = Language(rawValue: s) { return l }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
    }() {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    static var theme: AppTheme = {
        if let s = UserDefaults.standard.string(forKey: "theme"), let t = AppTheme(rawValue: s) { return t }
        return .original
    }() {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
}

/// 按当前语言选择文案
func tr(_ zh: String, _ en: String) -> String {
    Prefs.language == .zh ? zh : en
}

var appAccent: Color { Prefs.theme.accent }
var appWarn: Color { Prefs.theme.warn }
var appBad: Color { Prefs.theme.bad }
var appGood: Color { Prefs.theme.good }

/// 带主题色调的 HSB 颜色(用于图表)
func tc(_ h: Double, _ s: Double, _ b: Double) -> Color {
    let t = Prefs.theme
    return Color(hue: h, saturation: min(1, s * t.chartSat), brightness: min(1, b * t.chartBri))
}

/// 创建 DateFormatter 很贵(每个大文件行都会调用一次),所以按语言缓存起来复用
private enum FormatterCache {
    fileprivate static let lock = NSLock()
    private static var dates: [String: DateFormatter] = [:]
    private static var relatives: [String: RelativeDateTimeFormatter] = [:]

    /// DateFormatter 本身不是线程安全的:取用和格式化都在同一把锁里
    static func date() -> DateFormatter {
        let loc = Prefs.language.locale
        lock.lock(); defer { lock.unlock() }
        if let f = dates[loc.identifier] { return f }
        let f = DateFormatter()
        f.locale = loc
        f.dateStyle = .medium
        f.timeStyle = .short
        dates[loc.identifier] = f
        return f
    }

    static func relative() -> RelativeDateTimeFormatter {
        let loc = Prefs.language.locale
        lock.lock(); defer { lock.unlock() }
        if let f = relatives[loc.identifier] { return f }
        let f = RelativeDateTimeFormatter()
        f.locale = loc
        relatives[loc.identifier] = f
        return f
    }
}

func formatDate(_ d: Date) -> String {
    let f = FormatterCache.date()
    FormatterCache.lock.lock(); defer { FormatterCache.lock.unlock() }
    return f.string(from: d)
}

func relativeDate(_ d: Date) -> String {
    let f = FormatterCache.relative()
    FormatterCache.lock.lock(); defer { FormatterCache.lock.unlock() }
    return f.localizedString(for: d, relativeTo: Date())
}

extension Node {
    /// 界面上显示的名称(“小文件”合并节点随语言变化)
    var displayName: String {
        isAggregate ? tr("小文件", "Small items") : name
    }
}

// MARK: - 工具栏里的配色 / 语言菜单

struct SettingsMenus: View {
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AppTheme.allCases) { t in
                    Button {
                        Prefs.theme = t
                        onChange()
                    } label: {
                        if Prefs.theme == t {
                            Label(t.title, systemImage: "checkmark")
                        } else {
                            Text(t.title)
                        }
                    }
                }
            } label: {
                Label(tr("配色", "Theme"), systemImage: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("切换配色方案", "Change color theme"))

            Menu {
                ForEach(Language.allCases) { l in
                    Button {
                        Prefs.language = l
                        onChange()
                    } label: {
                        if Prefs.language == l {
                            Label(l.label, systemImage: "checkmark")
                        } else {
                            Text(l.label)
                        }
                    }
                }
            } label: {
                Label(Prefs.language.label, systemImage: "globe")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("切换语言", "Change language"))
        }
    }
}
