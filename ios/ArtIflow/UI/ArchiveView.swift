import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.state.savedQuestions.isEmpty {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: "还没有收藏的题目",
                    message: "在聊天里长按回答卡片即可收藏题目"
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(appState.state.savedQuestions, id: \.id) { saved in
                            savedRow(saved)
                                .id(saved.id)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        appState.removeSavedQuestion(savedQuestionId: saved.id)
                                    } label: {
                                        Label("移出", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // 教练“看依据题”跳转过来时滚动并高亮目标题，1.8s 后自动取消高亮
                    .onChange(of: appState.state.archiveFocusSavedQuestionId) { target in
                        guard let target = target, !target.isEmpty else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation { proxy.scrollTo(target, anchor: .center) }
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            await MainActor.run {
                                if appState.state.archiveFocusSavedQuestionId == target {
                                    appState.state.archiveFocusSavedQuestionId = nil
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("题目归档")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 单条收藏题：题面 / 图片缩略图 / 知识点标签 / 学科·题型 / 答案 / 回填 + 追问数
    @ViewBuilder
    private func savedRow(_ saved: SavedQuestion) -> some View {
        let isFocused = appState.state.archiveFocusSavedQuestionId == saved.id
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Text(saved.question).font(.headline).foregroundStyle(.appPrimary)
            // 缩略图：取第一张图展示
            if let first = saved.imagePreviewList.first, let img = UIImage(data: first) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(maxWidth: 120, maxHeight: 90)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                    .cardShadow(opacity: 0.05)
            }
            // 学科 / 题型标签
            if !saved.subject.isEmpty || !saved.questionType.isEmpty {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if !saved.subject.isEmpty {
                        chip(saved.subject, color: AppTheme.accent)
                    }
                    if !saved.questionType.isEmpty {
                        chip(saved.questionType, color: AppTheme.coachTint)
                    }
                }
            }
            if !saved.knowledgeTags.isEmpty {
                HStack {
                    ForEach(saved.knowledgeTags, id: \.self) { tag in
                        chip(tag, color: AppTheme.assistantAccent)
                    }
                }
            }
            MarkdownView(markdown: saved.answer, textColor: AppTheme.primaryText, fontSize: 15)
            HStack(spacing: AppTheme.Spacing.m) {
                Button {
                    appState.restoreSavedQuestionToComposer(savedQuestionId: saved.id)
                } label: {
                    Label("回填提问", systemImage: "arrow.uturn.backward").font(.caption)
                }
                if saved.followupCount > 0 {
                    Label("追问 \(saved.followupCount)", systemImage: "ellipsis.bubble")
                        .font(.caption2).foregroundStyle(.appSecondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(isFocused ? AppTheme.accentSoft.opacity(0.35) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    // 通用胶囊标签
    private func chip(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2).foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.s).padding(.vertical, 3)
            .background(color).clipShape(Capsule())
    }
}
