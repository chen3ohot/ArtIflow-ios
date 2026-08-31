import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.state.savedQuestions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical").font(.system(size: 44)).foregroundStyle(.appSecondary)
                    Text("还没有收藏的题目").font(.headline)
                    Text("在聊天里长按回答卡片即可收藏题目").font(.subheadline).foregroundStyle(.appSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.state.savedQuestions, id: \.id) { saved in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saved.question).font(.headline).foregroundStyle(.appPrimary)
                            if !saved.knowledgeTags.isEmpty {
                                HStack {
                                    ForEach(saved.knowledgeTags, id: \.self) { tag in
                                        Text(tag).font(.caption2).foregroundStyle(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(AppTheme.assistantAccent)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            MarkdownView(markdown: saved.answer, textColor: AppTheme.primaryText, fontSize: 15)
                                .frame(minHeight: 40)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("题目归档")
        .navigationBarTitleDisplayMode(.inline)
    }
}
