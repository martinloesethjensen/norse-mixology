import SwiftUI
import NorseMixologyCore

/// Settings → Backup: make a backup file, or restore from one (Backup spec §4).
/// The share sheet, restore summary and errors are presented from the app root
/// by `BackupPresenter`, so a file opened from Files works on any tab.
struct BackupSection: View {
    @Environment(BackupViewModel.self) private var backup
    @State private var isImporting = false

    var body: some View {
        Section {
            Button {
                Task { await backup.makeBackup() }
            } label: {
                HStack {
                    if backup.state == .preparing {
                        Text("Preparing backup…")
                        Spacer()
                        ProgressView()
                    } else {
                        Label("Back up now", systemImage: "square.and.arrow.up")
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(backup.isBusy)
            .listRowBackground(DesignTokens.surface)

            Button {
                isImporting = true
            } label: {
                HStack {
                    if backup.state == .reading {
                        Text("Opening backup…")
                        Spacer()
                        ProgressView()
                    } else {
                        Label("Restore from backup…", systemImage: "square.and.arrow.down")
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(backup.isBusy)
            .listRowBackground(DesignTokens.surface)
        } header: {
            Text("Backup")
        } footer: {
            Text("Your iPhone's own iCloud backup also includes this app's data. Use this to keep a copy you control or to move to a new phone.")
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.norseMixologyBackup]) { result in
            switch result {
            case .success(let url):
                Task { await backup.open(url: url) }
            case .failure(let error):
                AppLog.backup.error("File picker failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
