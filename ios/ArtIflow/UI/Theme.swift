import SwiftUI

// 统一的设计系统令牌：颜色、圆角、间距、阴影、排版
// 文本色使用语义色（自动适配深色模式），强调色用于品牌与主操作
enum AppTheme {
    // 品牌强调色（teal-green），用于主按钮、强调、选中态
    static let accent = Color(red: 0.05, green: 0.62, blue: 0.54)
    static let accentStrong = Color(red: 0.03, green: 0.5, blue: 0.43)
    static let accentSoft = Color(red: 0.86, green: 0.96, blue: 0.93)

    // 气泡 / 卡片色（用于 SwiftUI 视图层组合）
    static let userBubble = Color(red: 0.90, green: 0.96, blue: 0.94)
    static let cardBackground = Color.white
    static let background = Color(red: 0.97, green: 0.98, blue: 0.98)

    // 语义辅助色
    static let danger = Color(red: 0.83, green: 0.36, blue: 0.31)
    static let coachTint = Color(red: 0.36, green: 0.42, blue: 0.62)
    static let ankiTint = Color(red: 0.78, green: 0.49, blue: 0.20)

    // 助手强调色（沿用品牌绿），用于追问节点标签等
    static let assistantAccent = accent

    // Markdown 渲染文本色（注入到 WKWebView 的 HTML，固定深色以保证白底可读）
    static let primaryText = Color(red: 0.16, green: 0.20, blue: 0.19)

    // 圆角令牌
    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let pill: CGFloat = 22
    }

    // 间距令牌
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// 让 .appPrimary / .appSecondary 等点语法可用：映射到语义文本色，自动适配深色模式
extension ShapeStyle where Self == Color {
    static var appBackground: Color { AppTheme.background }
    static var appPrimary: Color { .primary }
    static var appSecondary: Color { .secondary }
    static var appAccent: Color { AppTheme.accent }
}

// 统一的轻阴影修饰符，用于卡片 / 气泡的层次感
extension View {
    func cardShadow(radius: CGFloat = 8, y: CGFloat = 2, opacity: Double = 0.08) -> some View {
        self.shadow(color: Color.black.opacity(opacity), radius: radius, x: 0, y: y)
    }
}
