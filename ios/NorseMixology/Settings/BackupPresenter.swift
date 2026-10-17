import SwiftUI
import NorseMixologyCore

/// Presents the backup share sheet, restore summary and errors from the app root,
/// so a `.nmbackup` opened from Files or AirDrop shows its summary on any tab.
struct BackupPresenter: ViewModifier {
    @Environment(BackupViewModel.self) private var backup

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isSharing) {
                if case .ready(let url) = backup.state {
                    ActivityView(items: [url]) { backup.cancel() }
                        .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: isRestoring) {
                RestoreSummarySheet()
            }
            .alert("Backup", isPresented: isFailed) {
                Button("OK") { backup.cancel() }
            } message: {
                Text(failureMessage)
            }
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == "nmbackup" else { return }
                Task { await backup.open(url: url) }
            }
    }

    private var isSharing: Binding<Bool> {
        Binding(
            get: { if case .ready = backup.state { return true } else { return false } },
            set: { if !$0 { backup.cancel() } }
        )
    }

    private var isRestoring: Binding<Bool> {
        Binding(
            get: {
                switch backup.state {
                case .opened, .restoring, .finished: return true
                default: return false
                }
            },
            set: { if !$0 { backup.cancel() } }
        )
    }

    private var isFailed: Binding<Bool> {
        Binding(
            get: { if case .failed = backup.state { return true } else { return false } },
            set: { if !$0 { backup.cancel() } }
        )
    }

    private var failureMessage: LocalizedStringKey {
        guard case .failed(let error) = backup.state else { return "Something went wrong." }
        switch error {
        case .notABackup: return "This file isn't a Norse Mixology backup."
        case .newerVersion: return "This backup was made by a newer version of the app. Update the app to restore it."
        case .damaged: return "This backup is damaged and can't be restored."
        case .outOfSpace: return "There isn't enough free space. Free some space and try again."
        case .exportFailed: return "Couldn't create the backup. Try again."
        case .restoreFailed: return "Couldn't restore. Nothing was changed."
        }
    }
}

extension View {
    func backupPresenter() -> some View {
        modifier(BackupPresenter())
    }
}
