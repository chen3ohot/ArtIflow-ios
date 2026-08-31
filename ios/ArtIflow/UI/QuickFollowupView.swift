import SwiftUI

struct QuickFollowupView: View {
    let spanId: String
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speech: SpeechRecognizer
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.l) {
                if let span = findSpanById(appState.state.messages, spanId: spanId) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                        Text("当前聚焦段落").font(.caption).foregroundStyle(.appSecondary)
                        Text(span.content).font(.callout)
                            .padding(AppTheme.Spacing.m)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                            .cardShadow(opacity: 0.06)
                    }
                }

                TextField("输入追问，或按住麦克风说话", text: $appState.state.input, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .padding(.vertical, AppTheme.Spacing.s + 2)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.pill))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.pill).stroke(Color.secondary.opacity(0.15)))

                Button {
                    if speech.isRecording { speech.stopTranscription() } else { speech.requestAuthorization { _ in speech.startTranscription() } }
                } label: {
                    Label(speech.isRecording ? "停止录音" : "语音追问", systemImage: speech.isRecording ? "waveform" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(speech.isRecording ? AppTheme.danger : AppTheme.accent)

                Spacer()
            }
            .padding()
            .tint(AppTheme.accent)
            .navigationTitle("精细追问")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { appState.state.quickFollowupSpanId = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        Task {
                            let question = appState.state.input
                            appState.state.input = ""
                            await appState.quickFollowup(spanId: spanId, question: question, isVoice: speech.isRecording)
                            appState.state.quickFollowupSpanId = nil
                            dismiss()
                        }
                    }
                    .bold()
                }
            }
            .onChange(of: speech.transcript) { value in
                if speech.isRecording { appState.state.input = value }
            }
        }
    }
}
