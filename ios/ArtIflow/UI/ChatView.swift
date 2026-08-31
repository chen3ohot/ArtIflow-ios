import SwiftUI
import PhotosUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speech: SpeechRecognizer

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.m) {
                        ForEach(appState.state.messages, id: \.id) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        if appState.state.isLoading {
                            // 助手侧的“正在输入”气泡，作为发送后即时反馈
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                                    TypingIndicator()
                                        .padding(.vertical, 4)
                                }
                                .padding(AppTheme.Spacing.m)
                                .background(AppTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                                .cardShadow()
                                Spacer(minLength: 48)
                            }
                            .padding(.horizontal, AppTheme.Spacing.m)
                            .id("loading-bubble")
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.m)
                }
                .onChange(of: appState.state.messages.count) { _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: appState.state.isLoading) { _ in
                    scrollToBottom(proxy)
                }
            }

            ChatInputBar()
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("ArtIflow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button { appState.startNewSession() } label: { Label("新对话", systemImage: "plus.message") }
                    if !appState.orderedSessions.isEmpty { Divider() }
                    ForEach(appState.orderedSessions, id: \.id) { session in
                        Button(session.title) { appState.switchToSession(id: session.id) }
                    }
                    if !appState.orderedSessions.isEmpty { Divider() }
                    ForEach(appState.orderedSessions, id: \.id) { session in
                        Button("删除 \(session.title)", role: .destructive) {
                            appState.deleteSession(id: session.id)
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { appState.openSettings() } label: { Image(systemName: "gearshape") }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if appState.state.isLoading {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("loading-bubble", anchor: .bottom) }
        } else if let last = appState.state.messages.last {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

struct ChatInputBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speech: SpeechRecognizer
    @State private var showingPicker = false
    @State private var isSending = false
    // 控制输入框焦点：发送后置 false 收起键盘
    @FocusState private var inputFocused: Bool

    private var canSend: Bool {
        !appState.state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !appState.pendingImages.isEmpty
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.s) {
            if !appState.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.s) {
                        ForEach(appState.pendingImages.indices, id: \.self) { index in
                            if let uiImage = UIImage(data: appState.pendingImages[index]) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                                    .cardShadow()
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.m)
            }

            HStack(alignment: .bottom, spacing: AppTheme.Spacing.s + 2) {
                Button {
                    showingPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(.appSecondary)
                        .frame(width: 30, height: 30)
                }
                .photosPicker(isPresented: $showingPicker, selection: $appState.photoPickerItems, maxSelectionCount: 4, matching: .images)

                Button {
                    appState.toggleVoiceRecording(speech)
                } label: {
                    Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(speech.isRecording ? AppTheme.danger : .appSecondary)
                        .frame(width: 30, height: 30)
                }

                TextField("问一道题，或拍照搜题", text: $appState.state.input, axis: .vertical)
                    .focused($inputFocused)
                    .lineLimit(1...5)
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .padding(.vertical, AppTheme.Spacing.s + 2)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.pill))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.pill).stroke(Color.secondary.opacity(0.15)))

                Button {
                    guard canSend, !isSending else { return }
                    isSending = true
                    inputFocused = false   // 立即收起键盘
                    Task {
                        defer { isSending = false }
                        if !appState.pendingImages.isEmpty {
                            let prompt = appState.state.input
                            appState.state.input = ""   // 清空提示词
                            await appState.sendImageQuestion(prompt: prompt)
                            appState.pendingImages = []
                            appState.photoPickerItems = []
                        } else {
                            await appState.sendTextQuestion()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(canSend ? AppTheme.accent : Color.secondary.opacity(0.4))
                        .clipShape(Circle())
                }
                .disabled(!canSend)
                .scaleEffect(isSending ? 0.88 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSending)
            }
            .onChange(of: appState.photoPickerItems) { _ in
                Task { await appState.loadPickedImages() }
            }
            .onChange(of: speech.transcript) { value in
                if speech.isRecording { appState.state.input = value }
            }
            .padding(.horizontal, AppTheme.Spacing.m)
            .padding(.top, AppTheme.Spacing.xs)
            .padding(.bottom, AppTheme.Spacing.s)
            .background(.regularMaterial)
        }
    }
}
