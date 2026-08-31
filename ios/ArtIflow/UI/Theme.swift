import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let cardBackground = Color(red: 1.0, green: 0.99, blue: 0.95)
    static let userBubble = Color(red: 0.96, green: 0.93, blue: 0.85)
    static let assistantAccent = Color(red: 0.18, green: 0.43, blue: 0.31)
    static let primaryText = Color(red: 0.18, green: 0.26, blue: 0.23)
    static let secondaryText = Color(red: 0.35, green: 0.45, blue: 0.41)
    static let divider = Color(red: 0.59, green: 0.69, blue: 0.62).opacity(0.4)
    static let danger = Color(red: 0.83, green: 0.36, blue: 0.31)
    static let coachTint = Color(red: 0.36, green: 0.42, blue: 0.62)
    static let ankiTint = Color(red: 0.78, green: 0.49, blue: 0.20)
}

extension Color {
    static let appBackground = AppTheme.background
    static let appPrimary = AppTheme.primaryText
    static let appSecondary = AppTheme.secondaryText
}
