import SwiftUI
import NorseMixologyCore

/// The Shopping list segment of the Cabinet tab: "Buy next" suggestions and the
/// user's list. Ticking an item moves it into the cabinet, with an undo toast.
struct ShoppingListView: View {
    @Environment(ShoppingListViewModel.self) private var shopping
    @Environment(CabinetViewModel.self) private var cabinet
    @Environment(RecipeBrowserViewModel.self) private var browser
    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var profile = UserTasteProfile.neutral
    @State private var lastReceipt: BoughtReceipt?
    @State private var boughtCount = 0
    @State private var toastTimer: Task<Void, Never>?

    private var cabinetStyleIds: Set<UUID> { Set(cabinet.items.map(\.ingredientStyleId)) }

    var body: some View {
        let index = taxonomyStore.index
        let entries = shopping.entries(in: index)
        let suggestions = BuyNextRanking.rank(entries: browser.entries, listedStyleIds: shopping.listedStyleIds, profile: profile)

        Group {
            if entries.isEmpty && suggestions.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to buy", systemImage: "cart")
                } description: {
                    Text("Your cabinet covers every recipe.")
                }
                .dsScreenBackground()
            } else {
                List {
                    if !suggestions.isEmpty {
                        Section {
                            ForEach(suggestions) { suggestion in
                                BuyNextRow(suggestion: suggestion) {
                                    shopping.add(suggestion.style, cabinetStyleIds: cabinetStyleIds)
                                }
                                .listRowBackground(DesignTokens.surface)
                            }
                        } header: {
                            sectionHeader(Text("Buy next"))
                        }
                    }
                    if !entries.isEmpty {
                        Section {
                            ForEach(entries) { entry in
                                ShoppingItemRow(
                                    entry: entry,
                                    familyName: entry.style.map { index.familyName(for: $0) } ?? "",
                                    onBought: { markBought(entry.item) }
                                )
                                .listRowBackground(DesignTokens.surface)
                                .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
                            }
                            .onDelete { offsets in
                                for offset in offsets {
                                    shopping.remove(entries[offset].item)
                                }
                            }
                        } header: {
                            sectionHeader(Text("Your list (\(entries.count))"))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .dsListBackground()
            }
        }
        .overlay(alignment: .bottom) {
            if let receipt = lastReceipt {
                UndoToast(
                    message: Text("Moved \(receipt.styleName) to your cabinet"),
                    onUndo: { undo(receipt) },
                    onDismiss: { dismissToast() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.success, trigger: boughtCount)
        .onAppear {
            profile = TasteProfileStore.load()
            shopping.pruneOwned(cabinetStyleIds: cabinetStyleIds)
            // Suggestions must reflect the cabinet as it is now, not as the Recipes tab last saw it.
            browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)
        }
        .onDisappear { dismissToast() }
    }

    private func sectionHeader(_ title: Text) -> some View {
        title
            .dsText(.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(DesignTokens.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func markBought(_ item: ShoppingItem) {
        var receipt: BoughtReceipt?
        withAnimation(reduceMotion ? nil : .default) {
            receipt = shopping.markBought(item, index: taxonomyStore.index)
        }
        guard let receipt else { return }
        cabinet.refresh()
        browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)
        boughtCount += 1
        AccessibilityNotification.Announcement(String(localized: "Moved \(receipt.styleName) to your cabinet")).post()
        showToast(for: receipt)
    }

    private func undo(_ receipt: BoughtReceipt) {
        shopping.undo(receipt)
        cabinet.refresh()
        browser.refresh(cabinet: cabinet.items, taxonomyStore: taxonomyStore)
        dismissToast()
    }

    /// 8 s, or until Undo/Dismiss while VoiceOver is running. A new tick replaces the toast.
    private func showToast(for receipt: BoughtReceipt) {
        toastTimer?.cancel()
        lastReceipt = receipt
        guard !voiceOverEnabled else { return }
        toastTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            lastReceipt = nil
        }
    }

    private func dismissToast() {
        toastTimer?.cancel()
        toastTimer = nil
        lastReceipt = nil
    }
}
