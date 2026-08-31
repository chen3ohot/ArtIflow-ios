import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.state.activePage) {
            NavigationStack { ChatView() }
                .tag(WorkspacePage.chat)
                .tabItem { Label("学习", systemImage: "bubble.left.and.bubble.right.fill") }

            NavigationStack { CoachView() }
                .tag(WorkspacePage.coach)
                .tabItem { Label("教练", systemImage: "figure.run") }

            NavigationStack { ArchiveView() }
                .tag(WorkspacePage.archive)
                .tabItem { Label("归档", systemImage: "books.vertical.fill") }

            NavigationStack { AnkiView() }
                .tag(WorkspacePage.anki)
                .tabItem { Label("测验", systemImage: "rectangle.stack.fill.badge.plus") }

            NavigationStack { ProfileView() }
                .tag(WorkspacePage.profile)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(AppTheme.accent)
        .sheet(isPresented: Binding(
            get: { appState.state.isSettingsOpen },
            set: { if !$0 { appState.cancelSettings() } else { appState.openSettings() } }
        )) {
            SettingsView()
        }
        .sheet(isPresented: Binding(
            get: { appState.state.quickFollowupSpanId != nil },
            set: { if !$0 { appState.state.quickFollowupSpanId = nil } }
        )) {
            if let spanId = appState.state.quickFollowupSpanId {
                QuickFollowupView(spanId: spanId)
            }
        }
        // 顶部即时提示（成功类 toast，1.8s 自动消失）
        .overlay(alignment: .top) {
            if let toast = appState.toast, appState.errorBanner == nil {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, AppTheme.Spacing.l)
                    .padding(.vertical, AppTheme.Spacing.s + 2)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .cardShadow()
                    .padding(.top, AppTheme.Spacing.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            await MainActor.run { if appState.toast == toast { appState.toast = nil } }
                        }
                    }
            }
        }
        // 底部持久错误条：发问失败时给明确反馈与可操作入口
        .overlay(alignment: .bottom) {
            if let banner = appState.errorBanner {
                ErrorBanner(text: banner, action: appState.errorAction ?? .none) {
                    appState.dismissErrorBanner()
                } onAction: {
                    switch appState.errorAction {
                    case .openSettings:
                        appState.dismissErrorBanner()
                        appState.openSettings()
                    default:
                        appState.dismissErrorBanner()
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.m)
                .padding(.bottom, AppTheme.Spacing.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appState.errorBanner)
        .animation(.easeInOut(duration: 0.25), value: appState.toast)
    }
}

private struct ErrorBanner: View {
    let text: String
    let action: ErrorBannerAction
    let onDismiss: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.danger)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.appPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: AppTheme.Spacing.s)
            if action == .openSettings {
                Button("去设置") { onAction() }
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.accent)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appSecondary)
                    .padding(4)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.vertical, AppTheme.Spacing.m)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .cardShadow(radius: 12, y: 4, opacity: 0.12)
    }
}
