import SwiftUI

struct CoachView: View {
    @EnvironmentObject var appState: AppState

    private var isEmpty: Bool {
        appState.state.coachDigest == nil && appState.state.coachMessages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEmpty {
                EmptyStateView(
                    systemImage: "figure.run.circle",
                    title: "AI 学习教练",
                    message: "点击右上角“生成今日复盘”，开始今天的针对性训练"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
                        if let digest = appState.state.coachDigest {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                                Text(digest.headline).font(.title3.bold()).foregroundStyle(AppTheme.coachTint)
                                Text(digest.summary).font(.callout).foregroundStyle(.appSecondary)
                                if !digest.focusAreas.isEmpty {
                                    Text("重点补强").font(.headline)
                                    ForEach(digest.focusAreas, id: \.point) { area in
                                        HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
                                            Text(area.level.label).font(.caption.bold()).foregroundStyle(.white)
                                                .padding(.horizontal, AppTheme.Spacing.s).padding(.vertical, AppTheme.Spacing.xs + 1)
                                                .background(area.level == .high ? AppTheme.danger : AppTheme.coachTint)
                                                .clipShape(Capsule())
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(area.point).font(.subheadline.bold())
                                                Text(area.diagnosis).font(.caption).foregroundStyle(.appSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(AppTheme.Spacing.l)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                            .cardShadow()
                        }

                        ForEach(appState.state.coachMessages, id: \.id) { message in
                            HStack {
                                if message.role == .user { Spacer(minLength: 40) }
                                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: AppTheme.Spacing.xs) {
                                    Text(message.text)
                                        .font(.body)
                                        .foregroundStyle(.appPrimary)
                                        .padding(AppTheme.Spacing.s + 2)
                                        .background(message.role == .user ? AppTheme.userBubble : AppTheme.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                                        .cardShadow(opacity: message.role == .user ? 0 : 0.06)
                                    Text(message.time).font(.caption2).foregroundStyle(.appSecondary)
                                }
                                if message.role == .assistant { Spacer(minLength: 40) }
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.l)
                }

                CoachInputBar()
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("AI 学习教练")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { appState.generateCoachDigest() } label: {
                    Label("今日复盘", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .onAppear {
            if appState.state.coachDigest == nil {
                appState.generateCoachDigest()
            }
        }
    }
}

private struct CoachInputBar: View {
    @EnvironmentObject var appState: AppState
    @State private var isSending = false

    private var canSend: Bool {
        !appState.state.coachInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.s) {
            TextField("和教练聊聊", text: $appState.state.coachInput, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, AppTheme.Spacing.m)
                .padding(.vertical, AppTheme.Spacing.s + 2)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.pill))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.pill).stroke(Color.secondary.opacity(0.15)))
            Button {
                guard canSend, !isSending else { return }
                isSending = true
                let text = appState.state.coachInput
                Task {
                    defer { isSending = false }
                    await appState.sendCoachMessage(text)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? AppTheme.coachTint : Color.secondary.opacity(0.4))
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(AppTheme.Spacing.m)
        .background(.regularMaterial)
    }
}
