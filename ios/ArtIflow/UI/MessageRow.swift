import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    @EnvironmentObject var appState: AppState

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

private struct UserBubble: View {
    let id: String
    let time: String
    let text: String
    let images: [Data]

    var body: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                if !images.isEmpty {
                    HStack {
                        ForEach(images.indices, id: \.self) { index in
                            if let ui = UIImage(data: images[index]) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                Text(text)
                    .font(.body)
                    .foregroundStyle(.appPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(time).font(.caption2).foregroundStyle(.appSecondary)
            }
        }
        .padding(.horizontal, 12)
    }
}

private struct AssistantBubble: View {
    let id: String
    let time: String
    let spans: [SpanData]
    let mainSpan: SpanData?
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(interactiveSpans, id: \.id) { span in
                    SpanCard(span: span)
                    if !(appState.state.histories[span.id] ?? []).isEmpty {
                        FollowupHistorySection(spanId: span.id)
                    }
                }
                Text(time).font(.caption2).foregroundStyle(.appSecondary)
                    .highPriorityGesture(swipeForFollowupEntry)
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 12)
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

private struct SpanCard: View {
    let span: SpanData
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MarkdownView(markdown: containsLatexMarkdown(span.content) ? normalizeLatexForMarkwon(span.content) : span.content, textColor: AppTheme.primaryText, fontSize: 16)
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button("自动讲解") { Task { await appState.autoExplain(spanId: span.id) } }
            Button("精细追问") { appState.state.quickFollowupSpanId = span.id }
            Button("收藏本题") { appState.saveCurrentQuestion() }
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

private struct FollowupHistorySection: View {
    let spanId: String
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(appState.state.histories[spanId] ?? [], id: \.id) { detail in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(detail.mode).font(.caption.bold()).foregroundStyle(AppTheme.assistantAccent)
                        Spacer()
                        Text(detail.time).font(.caption2).foregroundStyle(.appSecondary)
                    }
                    if let question = detail.question, !question.isEmpty {
                        Text(question).font(.callout).foregroundStyle(.appSecondary)
                    }
                    MarkdownView(markdown: containsLatexMarkdown(detail.answer) ? normalizeLatexForMarkwon(detail.answer) : detail.answer, textColor: AppTheme.primaryText, fontSize: 15)
                }
                .padding(10)
                .background(Color.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private extension Array where Element == SpanDetail {
    static var emptyList: [SpanDetail] { return [] }
}
