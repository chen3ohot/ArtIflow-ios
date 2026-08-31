import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message {
        case .user(let id, let time, let text, let imagePreviewBytes, let imagePreviewList):
            UserBubble(id: id, time: time, text: text, images: resolvedImages(imagePreviewList: imagePreviewList, fallback: imagePreviewBytes))
        case .assistant(let id, let time, let spans, let mainSpan, _):
            AssistantBubble(id: id, time: time, spans: spans, mainSpan: mainSpan)
        }
    }

    private func resolvedImages(imagePreviewList: [Data], fallback: Data?) -> [Data] {
        let list = imagePreviewList.isEmpty ? (fallback.map { [$0] } ?? []) : imagePreviewList
        return list
    }
}

// 用户气泡：右对齐，品牌浅绿填充
private struct UserBubble: View {
    let id: String
    let time: String
    let text: String
    let images: [Data]
    // 点击缩略图后弹出的全屏图片预览索引
    @State private var previewIndex: Int? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                if !images.isEmpty {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(images.indices, id: \.self) { index in
                            if let ui = UIImage(data: images[index]) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 92, height: 92)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                                    .cardShadow()
                                    .onTapGesture { previewIndex = index }
                            }
                        }
                    }
                }
                Text(text)
                    .font(.body)
                    .foregroundStyle(.appPrimary)
                    .padding(.horizontal, AppTheme.Spacing.l)
                    .padding(.vertical, AppTheme.Spacing.s + 2)
                    .background(AppTheme.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                    .textSelection(.enabled)
                Text(time).font(.caption2).foregroundStyle(.appSecondary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        // 全屏图片预览，支持多张左右翻看
        .fullScreenCover(item: Binding(
            get: { previewIndex.map { ImagePreviewAnchor(index: $0) } },
            set: { previewIndex = $0?.index }
        )) { _ in
            ImagePreviewSheet(images: images, startIndex: previewIndex ?? 0) { previewIndex = nil }
        }
    }
}

// fullScreenCover 需要可选 Identifiable 锚点
private struct ImagePreviewAnchor: Identifiable { let index: Int; var id: Int { index } }

// 全屏图片预览（对齐 Android ImagePreviewDialog）：上一张/下一张翻看
private struct ImagePreviewSheet: View {
    let images: [Data]
    @State var startIndex: Int
    let onClose: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $startIndex) {
                ForEach(images.indices, id: \.self) { i in
                    if let ui = UIImage(data: images[i]) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .tag(i)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            VStack {
                HStack {
                    Text("图片预览 \(startIndex + 1)/\(images.count)")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                    Spacer()
                    Button { onClose(); dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
}

// 助手气泡：左对齐，白底卡片 + 轻阴影
private struct AssistantBubble: View {
    let id: String
    let time: String
    let spans: [SpanData]
    let mainSpan: SpanData?
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                ForEach(interactiveSpans, id: \.id) { span in
                    SpanCard(span: span, messageId: id)
                    if !(appState.state.histories[span.id] ?? []).isEmpty {
                        FollowupHistorySection(spanId: span.id)
                    }
                }
                Text(time).font(.caption2).foregroundStyle(.appSecondary)
                    .highPriorityGesture(swipeForFollowupEntry)
            }
            Spacer(minLength: 48)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
    }

    private var interactiveSpans: [SpanData] {
        var result: [SpanData] = []
        if let mainSpan = mainSpan { result.append(mainSpan) }
        result.append(contentsOf: spans.filter { $0.id != mainSpan?.id })
        return result
    }

    private var swipeForFollowupEntry: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -60 {
                    appState.state.quickFollowupSpanId = id
                }
            }
    }
}

// 段落卡：内容为空时显示打字指示器，否则渲染 Markdown
private struct SpanCard: View {
    let span: SpanData
    let messageId: String   // 所属助手消息 id，用于按消息收藏/重新生成
    @EnvironmentObject var appState: AppState

    private var isSaved: Bool {
        appState.state.savedQuestions.contains { $0.sourceMessageId == messageId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            if span.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TypingIndicator()
                    .padding(.vertical, 4)
            } else {
                MarkdownView(
                    markdown: containsLatexMarkdown(span.content) ? normalizeLatexForMarkwon(span.content) : span.content,
                    textColor: AppTheme.primaryText,
                    fontSize: 16
                )
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .cardShadow()
        .contextMenu {
            Button("自动讲解") { Task { await appState.autoExplain(spanId: span.id) } }
            Button("精细追问") { appState.state.quickFollowupSpanId = messageId }
            Button(isSaved ? "取消收藏" : "收藏本题") { appState.toggleSavedQuestion(messageId: messageId) }
            Button("重新生成") { Task { await appState.refreshAssistantReply(messageId: messageId) } }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -80 {
                        Task { await appState.autoExplain(spanId: span.id) }
                    } else if value.translation.width > 80 {
                        appState.state.quickFollowupSpanId = span.id
                    }
                }
        )
    }
}

// 追问历史区
private struct FollowupHistorySection: View {
    let spanId: String
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            ForEach(appState.state.histories[spanId] ?? [], id: \.id) { detail in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack {
                        Text(detail.mode).font(.caption.bold()).foregroundStyle(AppTheme.assistantAccent)
                        Spacer()
                        Text(detail.time).font(.caption2).foregroundStyle(.appSecondary)
                    }
                    if let question = detail.question, !question.isEmpty {
                        Text(question).font(.callout).foregroundStyle(.appSecondary)
                    }
                    if detail.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TypingIndicator()
                    } else {
                        MarkdownView(
                            markdown: containsLatexMarkdown(detail.answer) ? normalizeLatexForMarkwon(detail.answer) : detail.answer,
                            textColor: AppTheme.primaryText,
                            fontSize: 15
                        )
                    }
                }
                .padding(AppTheme.Spacing.s + 2)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }
        }
    }
}

// 三个点交替缩放的打字指示器
struct TypingIndicator: View {
    @State private var phase: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.accent.opacity(0.55))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == CGFloat(i) ? 1.35 : 1.0)
                    .opacity(phase == CGFloat(i) ? 1.0 : 0.45)
                    .animation(.easeInOut(duration: 0.35), value: phase)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                phase = (phase + 1).truncatingRemainder(dividingBy: 3)
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }
}
