import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var showArkAdvanced = false
    @State private var showCustom = false
    @State private var showOpenSpeech = false
    @State private var showFlowStudy = false

    var body: some View {
        NavigationStack {
            Form {
                // 必填：只需填 API Key 即可开始
                Section {
                    SecureField("ARK / 豆包 API Key", text: $appState.state.settingsDraft.arkApiKey)
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
                    Text("快速开始 · 必填")
                } footer: {
                    Text("只需填入 ARK / 豆包 API Key 即可开始；其余保持默认。没有 Key？前往火山引擎方舟控制台创建。")
                }

                // ARK 高级：默认折叠
                Section {
                    DisclosureGroup("ARK 高级", isExpanded: $showArkAdvanced) {
                        TextField("模型", text: $appState.state.settingsDraft.arkModel)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Base URL", text: $appState.state.settingsDraft.arkBaseUrl)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Picker("端点", selection: $appState.state.settingsDraft.arkEndpoint) {
                            Text("Responses").tag("responses")
                            Text("Chat Completions").tag("chat/completions")
                        }
                        TextField("系统提示词", text: $appState.state.settingsDraft.arkSystemPrompt, axis: .vertical)
                            .lineLimit(2...6)
                        TextField("图片提问提示词", text: $appState.state.settingsDraft.imagePrompt, axis: .vertical)
                            .lineLimit(2...6)
                    }
                } footer: {
                    Text("可选：仅在需要更换模型、端点或提示词时展开。")
                }

                // 自定义兼容接口（可选）
                Section {
                    DisclosureGroup("自定义兼容接口 · 可选", isExpanded: $showCustom) {
                        TextField("Base URL", text: $appState.state.settingsDraft.customModelBaseUrl)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("API Key", text: $appState.state.settingsDraft.customModelApiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("模型名", text: $appState.state.settingsDraft.customModelName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text("可选：接入任意兼容 OpenAI 的接口。三项齐备时自动优先使用，并走 chat/completions。")
                }

                // OpenSpeech（可选）
                Section {
                    DisclosureGroup("OpenSpeech 语音 · 可选", isExpanded: $showOpenSpeech) {
                        SecureField("API Key", text: $appState.state.settingsDraft.openSpeechApiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Resource ID", text: $appState.state.settingsDraft.openSpeechResourceId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Submit URL", text: $appState.state.settingsDraft.openSpeechSubmitUrl)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Query URL", text: $appState.state.settingsDraft.openSpeechQueryUrl)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("UID", text: $appState.state.settingsDraft.openSpeechUid)
                    }
                } footer: {
                    Text("可选：如不使用语音追问可忽略。")
                }

                // FlowStudy（可选）
                Section {
                    DisclosureGroup("FlowStudy 对接 · 可选", isExpanded: $showFlowStudy) {
                        TextField("服务器地址", text: $appState.state.settingsDraft.flowStudyServerUrl)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("设备 ID", text: $appState.state.settingsDraft.flowStudyDeviceId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("设备 Token", text: $appState.state.settingsDraft.flowStudyDeviceToken)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text("可选：用于与后端配对 / 上传，按需填写。")
                }

                // 模型预设
                Section("模型预设") {
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
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { appState.cancelSettings() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { appState.saveSettings(); dismiss() }
                        .bold()
                }
            }
        }
        .tint(AppTheme.accent)
    }
}
