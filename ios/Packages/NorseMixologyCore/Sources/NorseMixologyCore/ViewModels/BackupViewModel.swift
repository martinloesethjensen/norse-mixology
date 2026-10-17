import Foundation
import Observation
import SwiftData

/// App-wide backup state (Backup spec §3–4). Building and opening a file run off
/// the main actor; the merge runs on the main context, which is saved first so
/// pending edits (a note mid-debounce) are included and never rolled back.
@MainActor
@Observable
public final class BackupViewModel {
    public enum State: Equatable {
        case idle
        case preparing
        case ready(URL)
        case reading
        case opened(BackupSummary)
        case restoring
        case finished(RestoreResult)
        case failed(BackupError)
    }

    public private(set) var state: State = .idle

    private let container: ModelContainer
    private let appVersion: String
    private let temporaryDirectory: URL
    private let onRestored: @MainActor () -> Void
    private var opened: OpenedBackup?

    public init(container: ModelContainer, appVersion: String,
                temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                onRestored: @escaping @MainActor () -> Void = {}) {
        self.container = container
        self.appVersion = appVersion
        self.temporaryDirectory = temporaryDirectory
        self.onRestored = onRestored
    }

    public var isBusy: Bool {
        switch state {
        case .preparing, .reading, .restoring: return true
        default: return false
        }
    }

    public func makeBackup() async {
        guard !isBusy else { return }
        reset()
        state = .preparing
        try? container.mainContext.save()
        let container = container, appVersion = appVersion, temporaryDirectory = temporaryDirectory
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try BackupWriter.write(container: container, appVersion: appVersion, temporaryDirectory: temporaryDirectory)
            }.value
            state = .ready(url)
        } catch {
            state = .failed(BackupError.from(error, otherwise: .exportFailed))
        }
    }

    /// Opens a file from the file picker or from "Open in" (Files, AirDrop).
    public func open(url: URL) async {
        guard !isBusy else { return }
        reset()
        state = .reading
        let temporaryDirectory = temporaryDirectory
        do {
            let backup = try await Task.detached(priority: .userInitiated) {
                try Self.withReadableFile(url) { try BackupReader.open($0, temporaryDirectory: temporaryDirectory) }
            }.value
            opened = backup
            state = .opened(backup.summary)
        } catch {
            state = .failed(BackupError.from(error, otherwise: .notABackup))
        }
    }

    public func confirmRestore() {
        guard case .opened = state, let backup = opened else { return }
        state = .restoring
        try? container.mainContext.save()
        do {
            let result = try BackupMerger.merge(backup, into: container.mainContext)
            closeOpened()
            state = .finished(result)
            onRestored()
        } catch {
            closeOpened()
            state = .failed(BackupError.from(error, otherwise: .restoreFailed))
        }
    }

    /// Dismisses whatever is showing and removes temporary files. Ignored while busy.
    public func cancel() {
        guard !isBusy else { return }
        reset()
        state = .idle
    }

    private func reset() {
        closeOpened()
        if case .ready(let url) = state {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    private func closeOpened() {
        opened?.close()
        opened = nil
    }

    /// Security-scoped, coordinated access, so files in iCloud Drive are downloaded before reading.
    nonisolated static func withReadableFile<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readableURL in
            result = Result { try body(readableURL) }
        }
        if let coordinationError { throw BackupError.from(coordinationError, otherwise: .notABackup) }
        guard let result else { throw BackupError.notABackup }
        return try result.get()
    }
}
