import SwiftUI

struct AnkiView: View {
    @EnvironmentObject var appState: AppState

    private var allCards: [AnkiCard] { appState.state.ankiCards }
    private var dueCards: [AnkiCard] { dueReviewCards(allCards) }
    private var decks: [AnkiDeckSummary] { buildAnkiDeckSummaries(allCards) }

    // 卡组专练模式下要练的卡片
    private var focusedDeckCards: [AnkiCard] {
        guard let deck = appState.state.focusedDeckName else { return [] }
        return allCards.filter { (normalizeDeckName($0.deckName) ?? DEFAULT_ANKI_DECK_NAME) == deck }
    }

    var body: some View {
        Group {
            if allCards.isEmpty {
                EmptyStateView(
                    systemImage: "rectangle.stack",
                    title: "还没有卡片",
                    message: "收藏题目后可生成记忆卡片"
                )
            } else if appState.state.isDueReviewMode {
                dueReviewMode
            } else if appState.state.focusedDeckName != nil {
                deckFocusedPractice
            } else {
                defaultList
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: Binding(
            get: { appState.state.showDeckPracticeSummary },
            set: { if !$0 { appState.dismissDeckPracticeSummary() } }
        )) {
            if let summary = appState.currentDeckPracticeSummary {
                DeckPracticeSummarySheet(summary: summary) {
                    appState.dismissDeckPracticeSummary()
                } onRestart: {
                    appState.restartDeckPracticeRound()
                } onClose: {
                    appState.closeDeckFocusedPractice()
                }
            }
        }
    }

    private var navigationTitle: String {
        if appState.state.isDueReviewMode { return "今日待复习" }
        if let deck = appState.state.focusedDeckName { return "卡组专练 · \(deck)" }
        return "Anki 测验"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if appState.state.isDueReviewMode {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("退出") { appState.closeDueReviewMode() }
            }
        } else if appState.state.focusedDeckName != nil {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("退出") { appState.closeDeckFocusedPractice() }
            }
        } else if !allCards.isEmpty {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { appState.openDueReviewQueue() } label: {
                    Label("待复习 \(dueCards.count)", systemImage: "clock.arrow.circlepath")
                }
                .disabled(dueCards.isEmpty)
            }
        }
    }

    // 默认列表：到期复习、卡组、全部卡片
    private var defaultList: some View {
        List {
            if !dueCards.isEmpty {
                Section("到期复习 \(dueCards.count)") {
                    Button {
                        appState.openDueReviewQueue()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill").foregroundStyle(AppTheme.ankiTint)
                            Text("开始今日待复习")
                            Spacer()
                            Text("\(dueCards.count) 张").foregroundStyle(.appSecondary)
                        }
                    }
                }
            }
            Section("卡组") {
                ForEach(decks, id: \.name) { deck in
                    Button {
                        appState.openDeckFocusedPractice(deckName: deck.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.name).font(.subheadline.bold()).foregroundStyle(.appPrimary)
                                if !deck.topTags.isEmpty {
                                    Text(deck.topTags.joined(separator: " · ")).font(.caption2).foregroundStyle(.appSecondary)
                                }
                            }
                            Spacer()
                            Text("\(deck.cardCount) 张").font(.caption).foregroundStyle(.appSecondary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.appSecondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if deck.name != DEFAULT_ANKI_DECK_NAME {
                            Button { appState.renameDeckPrompt = deck.name; appState.renameDeckNewName = deck.name; appState.showRenameDeckDialog = true } label: {
                                Label("重命名", systemImage: "pencil")
                            }.tint(.blue)
                            Button(role: .destructive) { appState.archiveAnkiDeck(deckName: deck.name) } label: {
                                Label("归档", systemImage: "archivebox")
                            }
                        }
                    }
                }
            }
            Section("全部卡片") {
                ForEach(allCards, id: \.id) { card in
                    CardReviewRow(card: card)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { appState.deleteAnkiCard(cardId: card.id) } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button { appState.beginEditAnkiCard(card) } label: {
                                Label("编辑", systemImage: "pencil")
                            }.tint(.blue)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: Binding(
            get: { appState.editingAnkiCardId != nil },
            set: { if !$0 { appState.cancelEditAnkiCard() } }
        )) {
            AnkiCardEditSheet(cardId: appState.editingAnkiCardId ?? "")
        }
        .sheet(isPresented: Binding(
            get: { appState.showRenameDeckDialog },
            set: { if !$0 { appState.showRenameDeckDialog = false } }
        )) {
            RenameDeckSheet()
        }
    }

    // 今日待复习模式
    private var dueReviewMode: some View {
        List {
            Section {
                ForEach(dueCards, id: \.id) { card in
                    CardReviewRow(card: card)
                }
            } header: {
                Text("今日到期 · \(dueCards.count) 张")
            } footer: {
                Text("标记掌握度后会按遗忘曲线安排下次复习。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // 卡组专练模式
    private var deckFocusedPractice: some View {
        List {
            Section {
                ForEach(focusedDeckCards, id: \.id) { card in
                    CardReviewRow(card: card)
                }
            } header: {
                Text("卡组 · \(appState.state.focusedDeckName ?? "")")
            } footer: {
                Text("练完所有卡片会自动弹出本轮汇总。")
            }
            Section {
                Button {
                    appState.openDeckPracticeSummary()
                } label: {
                    Label("查看本轮汇总", systemImage: "chart.bar.xaxis")
                }
                Button {
                    appState.restartDeckPracticeRound()
                } label: {
                    Label("重新开始一轮", systemImage: "arrow.clockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// 卡片复习行：正/反面 + 三档掌握度
private struct CardReviewRow: View {
    let card: AnkiCard
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack(alignment: .top) {
                Text(card.front).font(.headline)
                Spacer()
                if card.mastery != .unrated {
                    Text(card.mastery.label).font(.caption2)
                        .padding(.horizontal, AppTheme.Spacing.xs).padding(.vertical, 2)
                        .background(AppTheme.ankiTint.opacity(0.18)).clipShape(Capsule())
                }
            }
            Text(card.back).font(.callout).foregroundStyle(.appSecondary)
            if !card.tags.isEmpty {
                Text(card.tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.appSecondary)
            }
            HStack(spacing: AppTheme.Spacing.s) {
                ForEach([CardMasteryLevel.needsWork, .familiar, .proficient], id: \.self) { level in
                    Button {
                        appState.reviewAnkiCard(card, mastery: level)
                    } label: {
                        Text(level.label).font(.caption.bold())
                            .padding(.horizontal, AppTheme.Spacing.s).padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(masteryColor(level).opacity(0.18))
                            .foregroundStyle(masteryColor(level))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                    }
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func masteryColor(_ level: CardMasteryLevel) -> Color {
        switch level {
        case .needsWork: return AppTheme.danger
        case .familiar: return AppTheme.coachTint
        case .proficient: return AppTheme.accent
        default: return AppTheme.ankiTint
        }
    }
}

// 卡组专练汇总弹窗
private struct DeckPracticeSummarySheet: View {
    let summary: DeckPracticeSummary
    let onDismiss: () -> Void
    let onRestart: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("本轮统计") {
                    LabeledContent("卡组", value: summary.deckName)
                    LabeledContent("总卡片", value: "\(summary.totalCards)")
                    LabeledContent("已复习", value: "\(summary.reviewedCards)")
                    LabeledContent("生疏", value: "\(summary.needsWorkCount)")
                    LabeledContent("一般", value: "\(summary.familiarCount)")
                    LabeledContent("熟练", value: "\(summary.proficientCount)")
                }
                Section {
                    Button { onRestart(); onDismiss() } label: { Label("再来一轮", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { onClose() } label: { Label("结束专练", systemImage: "xmark") }
                }
            }
            .navigationTitle("卡组专练汇总")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { onDismiss() } }
            }
        }
    }
}

// 卡片编辑弹窗
private struct AnkiCardEditSheet: View {
    let cardId: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var front = ""
    @State private var back = ""
    @State private var tags = ""

    private var card: AnkiCard? { appState.state.ankiCards.first { $0.id == cardId } }

    var body: some View {
        NavigationStack {
            Form {
                Section("题面") { TextField("题面", text: $front, axis: .vertical).lineLimit(2...6) }
                Section("答案") { TextField("答案", text: $back, axis: .vertical).lineLimit(2...8) }
                Section("标签") { TextField("多个标签用空格分隔", text: $tags) }
            }
            .navigationTitle("编辑卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        appState.updateAnkiCard(cardId: cardId, front: front, back: back, tags: tags.split(separator: " ").map(String.init))
                        dismiss()
                    }.bold()
                }
            }
            .onAppear {
                guard let card = card else { return }
                front = card.front
                back = card.back
                tags = card.tags.joined(separator: " ")
            }
        }
    }
}

// 卡组重命名弹窗
private struct RenameDeckSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("新卡组名", text: $appState.renameDeckNewName)
                    .autocorrectionDisabled()
            }
            .navigationTitle("重命名卡组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        appState.renameAnkiDeck(deckName: appState.renameDeckPrompt, newDeckName: appState.renameDeckNewName)
                        dismiss()
                    }.bold()
                }
            }
        }
    }
}
