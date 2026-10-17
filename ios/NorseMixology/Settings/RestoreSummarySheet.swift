import SwiftUI
import NorseMixologyCore

/// The restore flow: what's in the file → Restore → what changed (Backup spec §4).
struct RestoreSummarySheet: View {
    @Environment(BackupViewModel.self) private var backup

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch backup.state {
                    case .opened(let summary):
                        summaryView(summary)
                    case .restoring:
                        ProgressView("Restoring…")
                            .frame(maxWidth: .infinity)
                    case .finished(let result):
                        resultView(result)
                    case .restoreFailed:
                        failedView
                    default:
                        EmptyView()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dsScreenBackground()
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(backup.state == .restoring)
    }

    private func summaryView(_ summary: BackupSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup from \(summary.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                line("\(summary.cabinetItems) cabinet items")
                line("\(summary.favourites) favourites")
                line("\(summary.shoppingItems) shopping list items")
                line("\(summary.takes) ratings and notes")
                line("\(summary.photos) photos")
            }
            Text("Nothing on this phone will be deleted.")
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
            primaryButton("Restore") { Task { await backup.confirmRestore() } }
            secondaryButton("Cancel") { backup.cancel() }
        }
    }

    private func resultView(_ result: RestoreResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if result.isEmpty {
                Text("Already up to date")
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Everything in this backup is already on this phone.")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                Text("Restored")
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                VStack(alignment: .leading, spacing: 6) {
                    if result.cabinetAdded > 0 { line("Added \(result.cabinetAdded) cabinet items") }
                    if result.favouritesAdded > 0 { line("Added \(result.favouritesAdded) favourites") }
                    if result.shoppingAdded > 0 { line("Added \(result.shoppingAdded) shopping list items") }
                    if result.takesAdded > 0 { line("Added \(result.takesAdded) ratings and notes") }
                    if result.takesUpdated > 0 { line("Updated \(result.takesUpdated) ratings and notes") }
                    if result.photosAdded > 0 { line("Added \(result.photosAdded) photos") }
                }
            }
            if result.photosSkippedForLimit > 0 {
                Text("\(result.photosSkippedForLimit) photos skipped (\(TakeLimits.maxPhotos)-photo limit)")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            primaryButton("Done") { backup.cancel() }
        }
    }

    /// Shown here rather than as an alert: the sheet is already up, and an alert
    /// can't present while it is dismissing.
    private var failedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn't restore")
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
            Text(failureMessage)
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
            primaryButton("Done") { backup.cancel() }
        }
    }

    private var failureMessage: LocalizedStringKey {
        guard case .restoreFailed(let error) = backup.state, error == .outOfSpace else {
            return "Couldn't restore. Nothing was changed."
        }
        return "There isn't enough free space. Free some space and try again."
    }

    private func line(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .dsText(.body)
            .foregroundStyle(DesignTokens.textPrimary)
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.dsPrimary)
    }

    private func secondaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
