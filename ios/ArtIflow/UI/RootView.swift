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
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            await MainActor.run { appState.toast = nil }
                        }
                    }
            }
        }
    }
}
