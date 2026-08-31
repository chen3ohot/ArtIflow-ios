import SwiftUI

/// 统一的空状态视图（iOS 16 自建，不依赖 iOS17 的 ContentUnavailableView）
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.6))
            VStack(spacing: AppTheme.Spacing.xs) {
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.appSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppTheme.Spacing.xl)
    }
}
