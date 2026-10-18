import Foundation
import ZIPFoundation

/// A validated backup, ready for `BackupRestorer`. Its photos are already
/// processed and wait as files in `directory`, which the caller deletes after restoring.
public struct BackupContents: Sendable {
    public struct PhotoFiles: Equatable, Sendable {
        public let full: URL
        public let thumbnail: URL
    }

    /// As written in the file; `data` may hold less after normalisation.
    public let manifest: BackupManifest
    public let data: BackupData
    public let photoFiles: [UUID: PhotoFiles]
    public let directory: URL
}

/// Reads and validates a `.norsebackup` before anything in the app is touched
/// (Backup spec §3). The file may come from anywhere, so only the expected
/// entry names are read, every entry is size-capped while it streams, and
/// every photo is re-processed.
public enum BackupReader {
    struct Limits {
        var manifestBytes = 1 << 20
        var dataBytes = 20 << 20
        var photoBytes = 25 << 20
        var totalBytes = 2 << 30

        static let `default` = Limits()
    }

    /// Just the manifest, for the restore confirmation.
    public static func readManifest(_ url: URL) throws -> BackupManifest {
        try readManifest(open(url), limits: .default, budget: Budget(limit: Limits.default.totalBytes))
    }

    /// Validates the whole file and extracts its photos into a new folder inside `tempDirectory`.
    /// On any error nothing is left behind.
    public static func read(_ url: URL, into tempDirectory: URL) throws -> BackupContents {
        try read(url, into: tempDirectory, limits: .default)
    }

    static func read(_ url: URL, into tempDirectory: URL, limits: Limits) throws -> BackupContents {
        let archive = try open(url)
        let budget = Budget(limit: limits.totalBytes)
        let manifest = try readManifest(archive, limits: limits, budget: budget)

        guard let dataEntry = archive[BackupFormat.dataPath], dataEntry.type == .file else {
            throw BackupError.damaged("no data.json")
        }
        let raw: BackupData
        do {
            raw = try BackupFormat.decoder().decode(
                BackupData.self, from: extract(dataEntry, from: archive, cap: limits.dataBytes, budget: budget))
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.damaged("data.json doesn't decode")
        }
        guard raw.counts == manifest.counts else { throw BackupError.damaged("counts don't match data.json") }
        let data = try validated(raw)

        let directory = tempDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var photoFiles: [UUID: BackupContents.PhotoFiles] = [:]
            for record in data.photos {
                guard let entry = archive[record.file], entry.type == .file else {
                    throw BackupError.damaged("missing \(record.file)")
                }
                let original = try extract(entry, from: archive, cap: limits.photoBytes, budget: budget)
                guard let processed = try? PhotoProcessor.processRestored(original) else {
                    throw BackupError.photoUnreadable(record.id)
                }
                let files = BackupContents.PhotoFiles(
                    full: directory.appendingPathComponent("\(record.id.uuidString).jpg"),
                    thumbnail: directory.appendingPathComponent("\(record.id.uuidString)-thumbnail.jpg"))
                try processed.full.write(to: files.full)
                try processed.thumbnail.write(to: files.thumbnail)
                photoFiles[record.id] = files
            }
            return BackupContents(manifest: manifest, data: data, photoFiles: photoFiles, directory: directory)
        } catch {
            try? fileManager.removeItem(at: directory)
            if let error = error as? BackupError { throw error }
            throw BackupError.damaged("couldn't extract photos")
        }
    }

    // MARK: - Archive

    private static func open(_ url: URL) throws -> Archive {
        do {
            return try Archive(url: url, accessMode: .read)
        } catch {
            // A cut-off backup still starts like a ZIP but has lost its directory at the end.
            throw startsLikeZIP(url) ? BackupError.damaged("unreadable archive") : BackupError.notABackup
        }
    }

    private static func startsLikeZIP(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    private static func readManifest(_ archive: Archive, limits: Limits, budget: Budget) throws -> BackupManifest {
        guard let entry = archive[BackupFormat.manifestPath], entry.type == .file else { throw BackupError.notABackup }
        let json: Data
        do {
            json = try extract(entry, from: archive, cap: limits.manifestBytes, budget: budget)
        } catch BackupError.damaged {
            throw BackupError.notABackup
        }

        // Check what the file is before trusting the rest of its shape.
        struct Header: Decodable {
            var format: String?
            var formatVersion: Int?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: json),
              header.format == BackupFormat.identifier, let version = header.formatVersion else {
            throw BackupError.notABackup
        }
        guard version <= BackupFormat.version else { throw BackupError.newerFormat(version) }
        guard version >= 1, let manifest = try? BackupFormat.decoder().decode(BackupManifest.self, from: json) else {
            throw BackupError.damaged("manifest.json doesn't decode")
        }
        return manifest
    }

    /// Bytes extracted so far, across the whole archive.
    private final class Budget {
        let limit: Int
        var used = 0
        init(limit: Int) { self.limit = limit }
    }

    private struct OverCap: Error {}

    /// Counts bytes as they stream, so a lying header or a zip bomb is stopped at the cap.
    private static func extract(_ entry: Entry, from archive: Archive, cap: Int, budget: Budget) throws -> Data {
        guard entry.uncompressedSize <= UInt64(cap),
              Int(entry.uncompressedSize) <= budget.limit - budget.used else { throw BackupError.tooLarge }
        var data = Data()
        let checksum: CRC32
        do {
            checksum = try archive.extract(entry) { chunk in
                guard data.count + chunk.count <= cap, budget.used + chunk.count <= budget.limit else { throw OverCap() }
                data.append(chunk)
                budget.used += chunk.count
            }
        } catch is OverCap {
            throw BackupError.tooLarge
        } catch {
            throw BackupError.damaged("can't extract \(entry.path)")
        }
        // The consumer form of `extract` returns the checksum but leaves comparing it to us.
        guard checksum == entry.checksum else { throw BackupError.damaged("checksum mismatch in \(entry.path)") }
        return data
    }

    // MARK: - Validation

    /// Rejects what the app could never have written and normalises what typing
    /// would have limited anyway (Backup spec §3).
    static func validated(_ data: BackupData) throws -> BackupData {
        func requireUnique<T>(_ items: [T], _ name: String, by key: (T) -> UUID) throws {
            guard Set(items.map(key)).count == items.count else { throw BackupError.damaged("duplicate \(name)") }
        }
        try requireUnique(data.cabinetItems, "cabinet item id", by: \.id)
        try requireUnique(data.favourites, "favourite id", by: \.id)
        try requireUnique(data.shoppingItems, "shopping item id", by: \.id)
        try requireUnique(data.takes, "take id", by: \.id)
        try requireUnique(data.takes, "take recipe", by: \.recipeId)
        try requireUnique(data.photos, "photo id", by: \.id)

        let unit = 0.0...1.0
        for item in data.cabinetItems {
            let p = item.flavorProfile
            let values = [p.sweetness, p.bitterness, p.smokiness, p.citrus, p.floral, p.spice, p.herbal, p.fruity, p.oaky, p.abv]
            guard values.allSatisfy(unit.contains) else { throw BackupError.damaged("flavour out of range") }
        }
        let taste = data.preferences.tasteProfile
        guard [taste.sweetness, taste.bitterness, taste.citrus, taste.smokiness, taste.herbal].allSatisfy(unit.contains) else {
            throw BackupError.damaged("taste profile out of range")
        }
        guard data.takes.allSatisfy({ TakeLimits.ratingRange.contains($0.rating) }) else {
            throw BackupError.damaged("rating out of range")
        }
        for photo in data.photos where photo.file != BackupFormat.photoPath(photo.id) {
            throw BackupError.damaged("unexpected photo file \(photo.file)")
        }
        let takeRecipes = Set(data.takes.map(\.recipeId))
        guard data.photos.allSatisfy({ takeRecipes.contains($0.recipeId) }) else {
            throw BackupError.damaged("photo without a take")
        }

        // The first `maxPhotos` per recipe, oldest first, as the photo strip allows.
        var kept: [UUID: Int] = [:]
        let photos = data.photos
            .sorted { ($0.dateAdded, $0.id.uuidString) < ($1.dateAdded, $1.id.uuidString) }
            .filter { photo in
                kept[photo.recipeId, default: 0] += 1
                return kept[photo.recipeId]! <= TakeLimits.maxPhotos
            }

        // Notes as `RecipeTakeService.setNotes` stores them; a take left empty doesn't exist.
        let takes = data.takes.compactMap { take -> BackupData.TakeRecord? in
            var take = take
            let limited = String(take.notes.prefix(TakeLimits.maxNotesLength))
            take.notes = limited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : limited
            let isEmpty = take.rating == 0 && take.notes.isEmpty && kept[take.recipeId, default: 0] == 0
            return isEmpty ? nil : take
        }

        var result = data
        result.photos = photos
        result.takes = takes
        return result
    }
}
