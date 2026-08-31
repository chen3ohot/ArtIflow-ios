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
                List {
                    ForEach(appState.state.savedQuestions, id: \.id) { saved in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                            Text(saved.question).font(.headline).foregroundStyle(.appPrimary)
                            if !saved.knowledgeTags.isEmpty {
                                HStack {
                                    ForEach(saved.knowledgeTags, id: \.self) { tag in
                                        Text(tag).font(.caption2).foregroundStyle(.white)
                                            .padding(.horizontal, AppTheme.Spacing.s).padding(.vertical, 3)
                                            .background(AppTheme.assistantAccent)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            MarkdownView(markdown: saved.answer, textColor: AppTheme.primaryText, fontSize: 15)
                        }
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("题目归档")
        .navigationBarTitleDisplayMode(.inline)
    }
}
