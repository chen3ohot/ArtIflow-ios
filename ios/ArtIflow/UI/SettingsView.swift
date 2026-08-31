import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("ARK / 豆包接口") {
                    TextField("API Key", text: $appState.state.settingsDraft.arkApiKey).autocorrectionDisabled()
                    TextField("模型", text: $appState.state.settingsDraft.arkModel)
                    TextField("Base URL", text: $appState.state.settingsDraft.arkBaseUrl).autocorrectionDisabled()
                    Picker("端点", selection: $appState.state.settingsDraft.arkEndpoint) {
                        Text("Responses").tag("responses")
                        Text("Chat Completions").tag("chat/completions")
                    }
                    TextField("系统提示词", text: $appState.state.settingsDraft.arkSystemPrompt, axis: .vertical).lineLimit(2...6)
                    TextField("图片提问提示词", text: $appState.state.settingsDraft.imagePrompt, axis: .vertical).lineLimit(2...6)
                }

                Section("自定义兼容接口（可选）") {
                    TextField("Base URL", text: $appState.state.settingsDraft.customModelBaseUrl).autocorrectionDisabled()
                    TextField("API Key", text: $appState.state.settingsDraft.customModelApiKey).autocorrectionDisabled()
                    TextField("模型名", text: $appState.state.settingsDraft.customModelName)
                }

                Section("OpenSpeech 语音（可选）") {
                    TextField("API Key", text: $appState.state.settingsDraft.openSpeechApiKey).autocorrectionDisabled()
                    TextField("Resource ID", text: $appState.state.settingsDraft.openSpeechResourceId)
                    TextField("Submit URL", text: $appState.state.settingsDraft.openSpeechSubmitUrl)
                    TextField("Query URL", text: $appState.state.settingsDraft.openSpeechQueryUrl)
                    TextField("UID", text: $appState.state.settingsDraft.openSpeechUid)
                }

                Section("FlowStudy 对接（可选）") {
                    TextField("服务器地址", text: $appState.state.settingsDraft.flowStudyServerUrl)
                    TextField("设备 ID", text: $appState.state.settingsDraft.flowStudyDeviceId)
                    SecureField("设备 Token", text: $appState.state.settingsDraft.flowStudyDeviceToken)
                }

                Section("模型预设") {
                    if appState.state.settingsDraft.customModelPresets.isEmpty {
                        Text("暂无预设").foregroundStyle(.appSecondary)
                    } else {
                        ForEach(appState.state.settingsDraft.customModelPresets, id: \.id) { preset in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(preset.name).font(.subheadline.bold())
                                    Text("\(preset.modelName) · \(preset.baseUrl)").font(.caption2).foregroundStyle(.appSecondary)
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
                        Button("保存当前为预设") {
                            let name = appState.state.settingsDraft.customModelName
                            appState.state.settingsDraft = appState.state.settingsDraft.saveCurrentModelPreset(name)
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { appState.cancelSettings() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { appState.saveSettings(); dismiss() } }
            }
        }
    }
}
