import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState

    private var topTopics: [(String, Int)] {
        appState.state.profile.topicHits.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    private var topKnowledge: [(String, Int)] {
        appState.state.knowledgePoints.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            Section("学习画像") {
                LabeledContent("当前阶段", value: appState.state.profile.level)
                LabeledContent("提问次数", value: "\(appState.state.profile.followups)")
                LabeledContent("语音追问", value: "\(appState.state.profile.voiceFollowups)")
            }
            Section("高频主题") {
                if topTopics.isEmpty {
                    Text("暂无数据").foregroundStyle(.appSecondary)
                } else {
                    ForEach(topTopics, id: \.0) { topic, count in
                        HStack { Text(topic); Spacer(); Text("\(count) 次").foregroundStyle(.appSecondary) }
                    }
                }
            }
            Section("高频知识点") {
                if topKnowledge.isEmpty {
                    Text("暂无数据").foregroundStyle(.appSecondary)
                } else {
                    ForEach(topKnowledge, id: \.0) { point, count in
                        HStack { Text(point); Spacer(); Text("\(count) 次").foregroundStyle(.appSecondary) }
                    }
                }
            }
            Section("数据") {
                LabeledContent("会话数", value: "\(appState.orderedSessions.count)")
                LabeledContent("收藏题数", value: "\(appState.state.savedQuestions.count)")
                LabeledContent("卡片数", value: "\(appState.state.ankiCards.count)")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
    }
}
