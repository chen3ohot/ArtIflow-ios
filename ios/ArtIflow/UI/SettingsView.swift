import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var showAdvanced = false
    @State private var showPresets = false

    var body: some View {
        NavigationStack {
            Form {
                // 唯一的提供商配置：OpenAI 兼容自定义端点
                Section {
                    TextField("Base URL", text: $appState.state.settingsDraft.customModelBaseUrl)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("API Key", text: $appState.state.settingsDraft.customModelApiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("模型名", text: $appState.state.settingsDraft.customModelName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack(spacing: AppTheme.Spacing.s) {
                        Button {
                            Task { await appState.testConnection() }
                        } label: {
                            HStack(spacing: 6) {
                                if appState.isTestingConnection {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text("测试连接")
                            }
                        }
                        .disabled(appState.isTestingConnection)
                        if let result = appState.connectionTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.hasPrefix("✅") ? AppTheme.accent : AppTheme.danger)
                        }
                    }
                } header: {
                    Text("OpenAI 兼容接口 · 必填")
                } footer: {
                    Text("填入任意兼容 OpenAI 协议的端点即可，统一走 chat/completions。示例：\n• OpenAI：https://api.openai.com/v1 + gpt-4o-mini\n• 自建/中转：https://your-host/v1 + 你的模型\nBase URL 可带或不带 /chat/completions 结尾。")
                }

                // 可选：系统提示词 / 图片提示词
                Section {
                    DisclosureGroup("提示词 · 可选", isExpanded: $showAdvanced) {
                        TextField("系统提示词", text: $appState.state.settingsDraft.arkSystemPrompt, axis: .vertical)
                            .lineLimit(2...6)
                        TextField("图片提问提示词", text: $appState.state.settingsDraft.imagePrompt, axis: .vertical)
                            .lineLimit(2...6)
                    }
                } footer: {
                    Text("可选：留空使用内置默认提示词。")
                }

                // 可选：模型预设
                Section {
                    DisclosureGroup("模型预设 · 可选", isExpanded: $showPresets) {
                        if appState.state.settingsDraft.customModelPresets.isEmpty {
                            Text("暂无预设").foregroundStyle(.appSecondary)
                        } else {
                            ForEach(appState.state.settingsDraft.customModelPresets, id: \.id) { preset in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name).font(.subheadline.bold())
                                        Text("\(preset.modelName) · \(preset.baseUrl)")
                                            .font(.caption2).foregroundStyle(.appSecondary)
                                    }
                                    Spacer()
                                    Button("应用") {
                                        appState.state.settingsDraft = appState.state.settingsDraft.applyModelPreset(preset)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        if appState.state.settingsDraft.hasCompleteCustomModel() {
                            Button {
                                let name = appState.state.settingsDraft.customModelName
                                appState.state.settingsDraft = appState.state.settingsDraft.saveCurrentModelPreset(name)
                            } label: {
                                Label("保存当前为预设", systemImage: "plus.circle")
                            }
                        }
                    }
                } footer: {
                    Text("可选：把当前端点存为预设，方便切换。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { appState.cancelSettings() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { appState.saveSettings(); dismiss() }.bold()
                }
            }
        }
        .tint(AppTheme.accent)
    }
}
