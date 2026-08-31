import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState

    // 学习阶段预设，点选即可一键切换；也可在下方文本框自定义
    private let levelPresets = ["初中 · 基础", "高一 · 基础夯实", "高二 · 进阶冲刺", "高三 · 冲刺备考", "大学 · 自由学习"]

    private var topTopics: [(String, Int)] {
        appState.state.profile.topicHits.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    private var topKnowledge: [(String, Int)] {
        appState.state.knowledgePoints.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            Section("学习画像") {
                // 当前阶段：可自定义，编辑时直接写活值，回车提交时持久化
                TextField("自定义学习阶段", text: Binding(
                    get: { appState.state.profile.level },
                    set: { appState.state.profile.level = $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { appState.updateProfileLevel(appState.state.profile.level) }
                LabeledContent("提问次数", value: "\(appState.state.profile.followups)")
                LabeledContent("语音追问", value: "\(appState.state.profile.voiceFollowups)")
            }
            Section("快速选择阶段") {
                ForEach(levelPresets, id: \.self) { preset in
                    Button {
                        appState.updateProfileLevel(preset)
                    } label: {
                        HStack {
                            Text(preset).foregroundStyle(.appPrimary)
                            Spacer()
                            if appState.state.profile.level == preset {
                                Image(systemName: "checkmark").foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
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
