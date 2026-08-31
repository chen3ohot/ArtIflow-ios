import SwiftUI

struct CoachView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let digest = appState.state.coachDigest {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(digest.headline).font(.title3.bold()).foregroundStyle(AppTheme.coachTint)
                            Text(digest.summary).font(.callout).foregroundStyle(.appSecondary)
                            if !digest.focusAreas.isEmpty {
                                Text("重点补强").font(.headline)
                                ForEach(digest.focusAreas, id: \.point) { area in
                                    HStack(alignment: .top) {
                                        Text(area.level.label).font(.caption.bold()).foregroundStyle(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(area.level == .high ? AppTheme.danger : AppTheme.coachTint)
                                            .clipShape(Capsule())
                                        VStack(alignment: .leading) {
                                            Text(area.point).font(.subheadline.bold())
                                            Text(area.diagnosis).font(.caption).foregroundStyle(.appSecondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    ForEach(appState.state.coachMessages, id: \.id) { message in
                        HStack {
                            if message.role == .user { Spacer(minLength: 40) }
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                                Text(message.text)
                                    .font(.body)
                                    .foregroundStyle(.appPrimary)
                                    .padding(10)
                                    .background(message.role == .user ? AppTheme.userBubble : Color.white.opacity(0.75))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(message.time).font(.caption2).foregroundStyle(.appSecondary)
                            }
                            if message.role == .assistant { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding()
            }

            HStack(alignment: .bottom) {
                TextField("和教练聊聊", text: $appState.state.coachInput, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Button {
                    let text = appState.state.coachInput
                    Task { await appState.sendCoachMessage(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(AppTheme.coachTint)
                }
                .disabled(appState.state.coachInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(.thinMaterial)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("AI 学习教练")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("生成今日复盘") { appState.generateCoachDigest() }
            }
        }
        .onAppear {
            if appState.state.coachDigest == nil {
                appState.generateCoachDigest()
            }
        }
    }
}
