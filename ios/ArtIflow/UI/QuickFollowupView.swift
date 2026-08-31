import SwiftUI

struct QuickFollowupView: View {
    let spanId: String
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speech: SpeechRecognizer
    @Environment(\.dismiss) var dismiss

    private var details: [SpanDetail] { appState.state.histories[spanId] ?? [] }
    private var focusedId: String? { appState.state.quickFollowupDetailId }
    // 当前聚焦追问；为空表示看段落根下的所有追问
    private var focusedDetail: SpanDetail? {
        guard let id = focusedId else { return nil }
        return details.first { $0.id == id }
    }
    // 从聚焦追问向上回溯到段落根的路径（仅祖先，不含聚焦追问本身）
    private var focusPath: [SpanDetail] {
        guard let id = focusedId else { return [] }
        var full = buildDetailPath(details: details, detailId: id)
        if !full.isEmpty { full.removeLast() }
        return full
    }
    // 当前层级下直接展开的追问（聚焦追问的子追问；未聚焦时为段落根下所有追问）
    private var visibleChildren: [SpanDetail] {
        if let id = focusedId {
            return details.filter { $0.parentDetailId == id }
        }
        return details.filter { $0.parentDetailId == nil || $0.parentDetailId?.isEmpty == true }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.m) {
                if let span = findSpanById(appState.state.messages, spanId: spanId) {
                    spanCard(span)
                }

                // 聚焦追问的当前层（问题+答案）
                if let current = focusedDetail {
                    focusedCard(current)
                } else if details.isEmpty {
                    Text("还没有追问，在下方输入即可对这一段精细提问")
                        .font(.caption).foregroundStyle(.appSecondary)
                }

                // 同层追问列表：点按可钻取下一层
                if !visibleChildren.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                            ForEach(visibleChildren, id: \.id) { detail in
                                Button {
                                    appState.openDetails(spanId: spanId, detailId: detail.id)
                                } label: {
                                    detailRow(detail)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }

                if focusedId != nil {
                    // 返回上一层 / 关闭追问分层
                    HStack(spacing: AppTheme.Spacing.s) {
                        Button {
                            _ = appState.stepBackQuickFollowupLayer()
                        } label: {
                            Label("返回上一层", systemImage: "arrow.uturn.backward")
                        }
                        Button {
                            appState.closeDetails()
                        } label: {
                            Label("回到追问列表", systemImage: "list.bullet")
                        }
                    }
                    .font(.caption)
                }

                Spacer(minLength: 0)

                inputBar
            }
            .padding()
            .tint(AppTheme.accent)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        appState.state.quickFollowupSpanId = nil
                        appState.closeDetails()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        Task {
                            let question = appState.state.input
                            appState.state.input = ""
                            await appState.quickFollowup(spanId: spanId, question: question, isVoice: speech.isRecording, parentDetailId: focusedId)
                            // 发送后保持面板开启，便于在同一层继续追问或钻取下一层
                            if speech.isRecording { speech.stopTranscription() }
                        }
                    }
                    .bold()
                    .disabled(appState.state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: speech.transcript) { value in
                if speech.isRecording { appState.state.input = value }
            }
        }
    }

    private var navigationTitle: String {
        if let current = focusedDetail { return "追问 · \((current.question ?? "").prefix(12))" }
        return "精细追问"
    }

    // 段落卡片
    private func spanCard(_ span: SpanData) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("当前聚焦段落").font(.caption).foregroundStyle(.appSecondary)
            Text(span.content).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.m)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .cardShadow(opacity: 0.06)
    }

    // 当前聚焦追问内容
    private func focusedCard(_ detail: SpanDetail) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if !focusPath.isEmpty {
                // 显示面包屑路径：根 → … → 当前
                Text(focusPath.map { ($0.question ?? "").prefix(10) }.joined(separator: " › "))
                    .font(.caption2).foregroundStyle(.appSecondary).lineLimit(1)
            }
            Text("Q：\(detail.question ?? "")").font(.subheadline.bold())
            Text(detail.answer).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.m)
        .background(AppTheme.accentSoft.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    // 同层追问行
    private func detailRow(_ detail: SpanDetail) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.question ?? "").font(.subheadline.bold()).lineLimit(2)
                Text(detail.answer).font(.caption).foregroundStyle(.appSecondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.appSecondary)
        }
        .padding(AppTheme.Spacing.s + 2)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .cardShadow(opacity: 0.05)
    }

    // 底部输入条（文本 + 语音）
    private var inputBar: some View {
        VStack(spacing: AppTheme.Spacing.s) {
            TextField(focusedId == nil ? "输入追问" : "对这条追问继续提问", text: $appState.state.input, axis: .vertical)
                .lineLimit(2...6)
                .padding(.horizontal, AppTheme.Spacing.m)
                .padding(.vertical, AppTheme.Spacing.s + 2)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.pill))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.pill).stroke(Color.secondary.opacity(0.15)))

            Button {
                appState.toggleVoiceRecording(speech)
            } label: {
                Label(speech.isRecording ? "停止录音" : "语音追问", systemImage: speech.isRecording ? "waveform" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(speech.isRecording ? AppTheme.danger : AppTheme.accent)
        }
    }
}
