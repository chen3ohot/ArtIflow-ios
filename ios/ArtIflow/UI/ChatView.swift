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
                    LazyVStack(spacing: 14) {
                        ForEach(appState.state.messages, id: \.id) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        if appState.state.isLoading {
                            HStack { ProgressView(); Text("生成中…").foregroundStyle(.appSecondary) }
                                .padding(.leading, 12)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: appState.state.messages.count) { _ in
                    if let last = appState.state.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            ChatInputBar()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("ArtIflow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("新对话") { appState.startNewSession() }
                    Divider()
                    ForEach(appState.orderedSessions, id: \.id) { session in
                        Button(session.title) { appState.switchToSession(id: session.id) }
                    }
                    Divider()
                    ForEach(appState.orderedSessions, id: \.id) { session in
                        Button("删除 \(session.title)", role: .destructive) { appState.deleteSession(id: session.id) }
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
}

struct ChatInputBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speech: SpeechRecognizer
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 8) {
            if !appState.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(appState.pendingImages.indices, id: \.self) { index in
                            if let uiImage = UIImage(data: appState.pendingImages[index]) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    showingPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(.appPrimary)
                }
                .photosPicker(isPresented: $showingPicker, selection: $appState.photoPickerItems, maxSelectionCount: 4, matching: .images)

                Button {
                    if speech.isRecording { speech.stopTranscription() } else { speech.requestAuthorization { _ in speech.startTranscription() } }
                } label: {
                    Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(speech.isRecording ? .red : .appPrimary)
                }

                TextField("问一道题，或拍照搜题", text: $appState.state.input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    Task {
                        if !appState.pendingImages.isEmpty {
                            await appState.sendImageQuestion(prompt: appState.state.input)
                            appState.pendingImages = []
                            appState.photoPickerItems = []
                        } else {
                            await appState.sendTextQuestion()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.appPrimary)
                }
                .disabled(appState.state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appState.pendingImages.isEmpty)
            }
            .onChange(of: appState.photoPickerItems) { _ in
                Task { await appState.loadPickedImages() }
            }
            .onChange(of: speech.transcript) { value in
                if speech.isRecording {
                    appState.state.input = value
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .background(.thinMaterial)
        }
    }
}
