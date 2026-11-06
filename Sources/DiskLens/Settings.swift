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

/// 带主题色调的 HSB 颜色(用于图表)
func tc(_ h: Double, _ s: Double, _ b: Double) -> Color {
    let t = Prefs.theme
    return Color(hue: h, saturation: min(1, s * t.chartSat), brightness: min(1, b * t.chartBri))
}

func formatDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Prefs.language.locale
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: d)
}

func relativeDate(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Prefs.language.locale
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
