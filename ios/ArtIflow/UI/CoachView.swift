import SwiftUI

struct CoachView: View {
    @EnvironmentObject var appState: AppState

    private var digest: CoachDailyDigest? { appState.state.coachDigest }
    private var training: DailyTrainingState { appState.state.dailyTraining }
    private var hasContent: Bool { digest != nil || !appState.state.coachMessages.isEmpty || training.isActive }

    var body: some View {
        VStack(spacing: 0) {
            if !hasContent {
                EmptyStateView(
                    systemImage: "figure.run.circle",
                    title: "AI 学习教练",
                    message: "点击右上角“今日训练”开始，或先在聊天里提问生成复盘"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
                        if training.isActive {
                            trainingHeader
                        }
                        if let digest = digest {
                            CoachDigestCard(digest: digest)
                        }
                        if let digest = digest, !digest.recommendedQuestions.isEmpty, !training.isActive {
                            recommendedQuestionsCard(digest.recommendedQuestions)
                        }
                        ForEach(appState.state.coachMessages, id: \.id) { message in
                            CoachBubble(message: message)
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
                Button { Task { await appState.startCoachTraining() } } label: {
                    Label("今日训练", systemImage: "sparkles")
                }
            }
        }
        .onAppear { appState.onCoachPageViewed() }
    }

    // 训练状态条：显示当前轮次与阶段
    private var trainingHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text("今日训练").font(.headline)
                Spacer()
                if training.phase == .awaitingAnswer {
                    Text("等待你作答").font(.caption).foregroundStyle(AppTheme.accent)
                } else if training.phase == .reviewingAnswer {
                    Text("正在批改").font(.caption).foregroundStyle(AppTheme.coachTint)
                } else if training.phase == .askingQuestion {
                    Text("正在出题").font(.caption).foregroundStyle(AppTheme.coachTint)
                }
            }
            if let round = training.currentRound {
                Text("\(round.title) · 第\(training.currentIndex + 1)/\(training.totalRounds) 题")
                    .font(.subheadline).foregroundStyle(.appSecondary)
            }
        }
        .padding(AppTheme.Spacing.m)
        .background(AppTheme.accentSoft.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    // 推荐题目卡片
    private func recommendedQuestionsCard(_ questions: [CoachRecommendedQuestion]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Text("今日推荐").font(.headline)
            ForEach(questions, id: \.id) { q in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(q.title).font(.subheadline.bold())
                    if !q.reason.isEmpty {
                        Text(q.reason).font(.caption).foregroundStyle(.appSecondary).lineLimit(2)
                    }
                    HStack(spacing: AppTheme.Spacing.s) {
                        Button { Task { await appState.startCoachRecommendedTraining(q) } } label: {
                            Label("开始训练", systemImage: "play.fill").font(.caption.bold())
                        }
                        Button { appState.askCoachAboutRecommendation(q) } label: {
                            Label("问理由", systemImage: "questionmark.circle").font(.caption)
                        }
                        if q.anchorSavedQuestionId != nil {
                            Button { appState.jumpToCoachRecommendationBasis(q) } label: {
                                Label("看依据题", systemImage: "arrow.right.circle").font(.caption)
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.s + 2)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                .cardShadow(opacity: 0.05)
            }
        }
    }
}

// 复盘摘要卡
private struct CoachDigestCard: View {
    let digest: CoachDailyDigest
    @EnvironmentObject var appState: AppState

    var body: some View {
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
}

// 教练消息气泡
private struct CoachBubble: View {
    let message: CoachChatMessage
    @EnvironmentObject var appState: AppState

    private var quickActions: [CoachReplyQuickAction] {
        buildCoachReplyQuickActions(message: message, digest: appState.state.coachDigest, training: appState.state.dailyTraining)
    }

    var body: some View {
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
                if message.role == .assistant && !quickActions.isEmpty {
                    // 助手回复下方的快捷追问胶囊，对齐 Android coach quick actions
                    FlowChips(items: quickActions.map { $0.label }) { index in
                        appState.sendCoachQuickAction(quickActions[index].prompt)
                    }
                }
                Text(message.time).font(.caption2).foregroundStyle(.appSecondary)
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

// 简单的流式胶囊布局：自动换行排列快捷追问按钮
private struct FlowChips: View {
    let items: [String]
    let onTap: (Int) -> Void

    var body: some View {
        FlexibleHStack(items: items) { index, label in
            Button { onTap(index) } label: {
                Text(label).font(.caption.bold())
                    .padding(.horizontal, AppTheme.Spacing.s).padding(.vertical, AppTheme.Spacing.xs + 1)
                    .background(AppTheme.accentSoft.opacity(0.6))
                    .foregroundStyle(AppTheme.accent)
                    .clipShape(Capsule())
            }
        }
    }
}

// 手写简易换行布局（iOS16 无原生 FlowLayout）
private struct FlexibleHStack<Content: View>: View {
    let items: [String]
    let content: (Int, String) -> Content

    var body: some View {
        GeometryReader { geo in
            self.generateContent(in: geo.size)
        }
        .frame(height: computeHeight())
    }

    private func generateContent(in size: CGSize) -> some View {
        var width = CGFloat.zero
        var rows: [[Int]] = [[]]
        for (i, item) in items.enumerated() {
            let w = CGFloat(item.count) * 14 + 28
            if width + w > size.width && !rows[rows.count - 1].isEmpty {
                rows.append([i]); width = w
            } else {
                rows[rows.count - 1].append(i); width += w + AppTheme.Spacing.s
            }
        }
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: AppTheme.Spacing.s) {
                    ForEach(rows[row], id: \.self) { i in
                        content(i, items[i])
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func computeHeight() -> CGFloat {
        let rowHeight: CGFloat = 30
        let perRow = max(1, Int(UIScreen.main.bounds.width / 120))
        let rows = (items.count + perRow - 1) / perRow
        return CGFloat(rows) * (rowHeight + AppTheme.Spacing.xs)
    }
}

// 教练输入条：训练等待作答时提交作答，否则发送普通教练消息
private struct CoachInputBar: View {
    @EnvironmentObject var appState: AppState
    @State private var isSending = false

    private var awaitingAnswer: Bool { appState.state.dailyTraining.phase == .awaitingAnswer }
    private var canSend: Bool {
        !appState.state.coachInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.s) {
            TextField(awaitingAnswer ? "输入你的作答，提交批改" : "和教练聊聊", text: $appState.state.coachInput, axis: .vertical)
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
                    if awaitingAnswer {
                        await appState.submitDailyTrainingAnswer(text, fromCoachInput: true)
                    } else {
                        await appState.sendCoachMessage(text)
                    }
                }
            } label: {
                Image(systemName: awaitingAnswer ? "checkmark" : "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? (awaitingAnswer ? AppTheme.accent : AppTheme.coachTint) : Color.secondary.opacity(0.4))
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(AppTheme.Spacing.m)
        .background(.regularMaterial)
    }
}
