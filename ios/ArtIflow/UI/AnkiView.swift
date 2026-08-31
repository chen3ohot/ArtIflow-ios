import SwiftUI

struct AnkiView: View {
    @EnvironmentObject var appState: AppState

    private var dueCards: [AnkiCard] { dueReviewCards(appState.state.ankiCards) }
    private var decks: [AnkiDeckSummary] { buildAnkiDeckSummaries(appState.state.ankiCards) }

    var body: some View {
        Group {
            if appState.state.ankiCards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack").font(.system(size: 44)).foregroundStyle(.appSecondary)
                    Text("还没有卡片").font(.headline)
                    Text("收藏题目后可生成记忆卡片").font(.subheadline).foregroundStyle(.appSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("到期复习") {
                        ForEach(dueCards, id: \.id) { card in
                            CardReviewRow(card: card)
                        }
                    }
                    Section("卡组") {
                        ForEach(decks, id: \.name) { deck in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(deck.name).font(.subheadline.bold())
                                    if !deck.topTags.isEmpty {
                                        Text(deck.topTags.joined(separator: " · ")).font(.caption2).foregroundStyle(.appSecondary)
                                    }
                                }
                                Spacer()
                                Text("\(deck.cardCount) 张").font(.caption).foregroundStyle(.appSecondary)
                            }
                        }
                    }
                    Section("全部卡片") {
                        ForEach(appState.state.ankiCards, id: \.id) { card in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.front).font(.subheadline.bold())
                                Text(card.back).font(.caption).foregroundStyle(.appSecondary).lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Anki 测验")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CardReviewRow: View {
    let card: AnkiCard
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.front).font(.headline)
            Text(card.back).font(.callout).foregroundStyle(.appSecondary)
            HStack(spacing: 8) {
                ForEach([CardMasteryLevel.needsWork, .familiar, .proficient], id: \.self) { level in
                    Button {
                        appState.reviewAnkiCard(card, mastery: level)
                    } label: {
                        Text(level.label).font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(AppTheme.ankiTint.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .tint(AppTheme.ankiTint)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
