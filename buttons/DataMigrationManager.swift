//
//  DataMigrationManager.swift
//  Pushup Hero
//
//  Data Migration and Backup Manager
//  Protects user data during app upgrades
//

import Foundation

/// What happened during the launch-time data check.
///
/// This is deliberately richer than a Bool: "recovery succeeded" and "nothing
/// needed doing" are both successes, but only one of them means the user should
/// go and check their history.
enum MigrationOutcome {
    /// No data file and no evidence there ever was one.
    case freshInstall
    /// Existing data verified intact.
    case ok(recordCount: Int)
    /// First launch after upgrading from a build without version tracking.
    /// A pre-upgrade snapshot has been taken.
    case upgradedFromLegacy(recordCount: Int)
    /// The live file was unusable and a backup was restored in its place.
    case recovered(from: String, recordCount: Int)
    /// The live file was unusable and nothing could be restored. The original
    /// bytes have been quarantined, never deleted.
    case failed(reason: String)

    /// True when the user's history may differ from what they last saw.
    var needsUserAttention: Bool {
        switch self {
        case .recovered, .failed: return true
        case .freshInstall, .ok, .upgradedFromLegacy: return false
        }
    }
}

class DataMigrationManager {

    static let shared = DataMigrationManager()

    private let fileManager = FileManager.default

    /// How many routine backups to retain. Snapshots taken immediately before a
    /// schema upgrade are exempt — see cleanupOldBackups().
    private let routineBackupsToKeep = 5

    private let currentDataVersion = 1

    struct DataVersion: Codable {
        let version: Int
        let lastBackupDate: Date
        let appVersion: String
        /// Records present at the last verified-good launch. The app has no way
        /// to delete a workout, so this count must never decrease; if it does,
        /// something has eaten history and we want to notice.
        let recordCount: Int?
    }

    struct BackupInfo {
        let filename: String
        let url: URL
        /// Taken from the timestamp embedded in the filename. Filesystem
        /// creation dates are useless here because copyItem() copies the
        /// source's creation date onto every backup, leaving them all identical.
        let timestamp: Date
        let reason: String
        let fileSize: Int64
    }

    // MARK: - Public Interface

    /// Runs the launch-time data check. Never deletes user data: anything that
    /// cannot be read is moved into the backup folder rather than removed.
    func performMigrationIfNeeded() -> MigrationOutcome {
        guard let dataURL = DataArchive.fileURL else {
            return .failed(reason: "Could not locate the documents directory.")
        }

        createBackupFolderIfNeeded()

        let savedVersion = loadDataVersion()
        let dataFileExists = fileManager.fileExists(atPath: dataURL.path)

        // A missing version file does NOT mean a fresh install. Upgrading from
        // a build that predates version tracking looks exactly the same, and
        // that is precisely the launch where a snapshot matters most.
        guard dataFileExists else {
            if savedVersion == nil && listBackups().isEmpty {
                print("First launch detected - initializing data version tracking")
                saveDataVersion(recordCount: 0)
                return .freshInstall
            }
            print("Data file missing but history is expected - attempting recovery")
            return attemptRecovery(reason: "data file missing")
        }

        // Validate before backing up, so a corrupt file never becomes a backup
        // and pushes the last good snapshots out of the retention window.
        let validation = validateDataFile()
        guard validation.isValid, let records = validation.recordCount else {
            print("Data validation failed: \(validation.error ?? "unknown error")")
            quarantineCurrentDataFile(reason: "corrupt")
            return attemptRecovery(reason: validation.error ?? "validation failed")
        }

        let isLegacyUpgrade = savedVersion == nil
        _ = createBackup(reason: isLegacyUpgrade ? "pre_migration" : "pre_launch")

        if let previous = savedVersion?.recordCount, records < previous {
            // Not fatal on its own — but worth a loud note, and worth keeping
            // the snapshot we just took out of the routine cleanup.
            print("WARNING: record count dropped from \(previous) to \(records)")
        }

        saveDataVersion(recordCount: records)
        cleanupOldBackups()

        if isLegacyUpgrade {
            print("Upgraded from a pre-versioning build - snapshot taken, \(records) records intact")
            return .upgradedFromLegacy(recordCount: records)
        }

        print("Data migration check complete - \(records) records intact")
        return .ok(recordCount: records)
    }

    // MARK: - Backup Management

    /// Creates a backup of the current data file. Skips the write when the file
    /// is byte-identical to the newest existing backup, so repeated launches
    /// cannot flush the useful history out of the retention window.
    @discardableResult
    func createBackup(reason: String = "manual") -> Bool {
        guard let dataURL = DataArchive.fileURL,
              let backupFolder = DataArchive.backupFolderURL,
              fileManager.fileExists(atPath: dataURL.path) else {
            print("Cannot create backup - no data file exists")
            return false
        }

        createBackupFolderIfNeeded()

        guard let current = try? Data(contentsOf: dataURL) else {
            print("Cannot create backup - data file unreadable")
            return false
        }

        if let newest = listBackups().first,
           let existing = try? Data(contentsOf: newest.url),
           existing == current {
            print("Backup skipped - identical to \(newest.filename)")
            return true
        }

        let backupURL = backupFolder.appendingPathComponent("Data_\(reason)_\(Self.timestampFormatter.string(from: Date()))")

        do {
            try current.write(to: backupURL, options: .atomic)
            print("Backup created: \(backupURL.lastPathComponent)")
            return true
        } catch {
            print("Backup failed: \(error.localizedDescription)")
            return false
        }
    }

    /// All backups, newest first, ordered by the timestamp in the filename.
    func listBackups() -> [BackupInfo] {
        guard let backupFolder = DataArchive.backupFolderURL,
              let files = try? fileManager.contentsOfDirectory(atPath: backupFolder.path) else {
            return []
        }

        let backups = files.compactMap { filename -> BackupInfo? in
            guard filename.hasPrefix("Data_") else { return nil }
            let url = backupFolder.appendingPathComponent(filename)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? Int64) ?? 0
            let (reason, timestamp) = Self.parse(filename: filename)
            return BackupInfo(filename: filename, url: url, timestamp: timestamp, reason: reason, fileSize: size)
        }
        return backups.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Data Recovery

    /// Walks backups newest-first, validating each one *before* it is written
    /// over the live file. Iterative, so a folder full of bad backups cannot
    /// blow the stack the way mutual recursion did.
    private func attemptRecovery(reason: String) -> MigrationOutcome {
        guard let dataURL = DataArchive.fileURL else {
            return .failed(reason: "Could not locate the documents directory.")
        }

        let candidates = listBackups()
        guard !candidates.isEmpty else {
            print("No backups available for recovery")
            return .failed(reason: reason)
        }

        for backup in candidates {
            guard let objects = try? DataArchive.read(from: backup.url),
                  validate(objects).isValid else {
                print("Skipping unusable backup: \(backup.filename)")
                continue
            }

            do {
                // Atomic write; the live file is replaced only once the
                // replacement is fully on disk.
                try DataArchive.write(objects, to: dataURL)
            } catch {
                print("Could not restore \(backup.filename): \(error.localizedDescription)")
                continue
            }

            print("Recovered \(objects.count) records from \(backup.filename)")
            saveDataVersion(recordCount: objects.count)
            return .recovered(from: backup.filename, recordCount: objects.count)
        }

        print("No usable backup found")
        return .failed(reason: reason)
    }

    /// Moves an unreadable data file aside instead of deleting it. If a future
    /// build learns to read it, the bytes are still there.
    /// Public entry point for the save path: preserve a data file the app could
    /// not decode, before a save is allowed to replace it.
    func quarantineUnreadableDataFile() {
        quarantineCurrentDataFile(reason: "unreadable")
    }

    private func quarantineCurrentDataFile(reason: String) {
        guard let dataURL = DataArchive.fileURL,
              let backupFolder = DataArchive.backupFolderURL,
              fileManager.fileExists(atPath: dataURL.path) else { return }

        createBackupFolderIfNeeded()
        let destination = backupFolder.appendingPathComponent("Quarantine_\(reason)_\(Self.timestampFormatter.string(from: Date()))")
        do {
            try fileManager.moveItem(at: dataURL, to: destination)
            print("Quarantined unreadable data file as \(destination.lastPathComponent)")
        } catch {
            print("Could not quarantine data file: \(error.localizedDescription)")
        }
    }

    // MARK: - Data Validation

    struct ValidationResult {
        let isValid: Bool
        let error: String?
        let recordCount: Int?
    }

    /// Validates the live data file using the same decoder the app loads with.
    func validateDataFile() -> ValidationResult {
        guard let dataURL = DataArchive.fileURL else {
            return ValidationResult(isValid: false, error: "Documents directory unavailable", recordCount: nil)
        }
        guard fileManager.fileExists(atPath: dataURL.path) else {
            return ValidationResult(isValid: false, error: "File does not exist", recordCount: nil)
        }

        do {
            let objects = try DataArchive.read(from: dataURL)
            return validate(objects)
        } catch {
            return ValidationResult(isValid: false, error: error.localizedDescription, recordCount: nil)
        }
    }

    private func validate(_ objects: [DataObject]) -> ValidationResult {
        for (index, object) in objects.enumerated() {
            if object.numberOfPushups < 0 {
                return ValidationResult(isValid: false, error: "Invalid pushup count at index \(index)", recordCount: objects.count)
            }
            if object.dateOfSave.timeIntervalSince1970 < 0 {
                return ValidationResult(isValid: false, error: "Invalid date at index \(index)", recordCount: objects.count)
            }
        }
        return ValidationResult(isValid: true, error: nil, recordCount: objects.count)
    }

    // MARK: - Version Management

    private func loadDataVersion() -> DataVersion? {
        guard let url = DataArchive.versionFileURL,
              let data = try? Data(contentsOf: url),
              let version = try? JSONDecoder().decode(DataVersion.self, from: data) else {
            return nil
        }
        return version
    }

    private func saveDataVersion(recordCount: Int) {
        guard let url = DataArchive.versionFileURL else { return }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let version = DataVersion(version: currentDataVersion,
                                  lastBackupDate: Date(),
                                  appVersion: appVersion,
                                  recordCount: recordCount)

        if let data = try? JSONEncoder().encode(version) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Helper Methods

    /// Filenames embed the timestamp because copyItem/creation dates cannot be
    /// trusted to order backups.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func parse(filename: String) -> (reason: String, timestamp: Date) {
        // Data_<reason>_<timestamp>
        let parts = filename.components(separatedBy: "_")
        guard parts.count >= 3, let parsed = timestampFormatter.date(from: parts[parts.count - 1]) else {
            return (parts.count >= 2 ? parts[1] : "unknown", .distantPast)
        }
        return (parts[1..<(parts.count - 1)].joined(separator: "_"), parsed)
    }

    private func createBackupFolderIfNeeded() {
        guard let backupFolder = DataArchive.backupFolderURL else { return }
        if !fileManager.fileExists(atPath: backupFolder.path) {
            try? fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Trims routine backups. Pre-upgrade and quarantine snapshots are kept
    /// permanently — they are the ones that matter if an upgrade goes wrong,
    /// and they are created at most once per schema change.
    private func cleanupOldBackups() {
        let routine = listBackups().filter { $0.reason != "pre_migration" && $0.reason != "pre_import" }
        guard routine.count > routineBackupsToKeep else { return }

        for backup in routine.dropFirst(routineBackupsToKeep) {
            try? fileManager.removeItem(at: backup.url)
            print("Removed old backup: \(backup.filename)")
        }
    }

    // MARK: - Manual Operations

    /// Exports the current data file to a user-accessible location.
    func exportDataForBackup(to url: URL) -> Bool {
        guard let dataURL = DataArchive.fileURL,
              fileManager.fileExists(atPath: dataURL.path) else {
            return false
        }

        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.copyItem(at: dataURL, to: url)
            print("Data exported successfully")
            return true
        } catch {
            print("Export failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Imports data from a user-provided backup file. The candidate is validated
    /// before it is allowed anywhere near the live file.
    func importDataFromBackup(from url: URL) -> Bool {
        guard let dataURL = DataArchive.fileURL else { return false }

        let objects: [DataObject]
        do {
            objects = try DataArchive.read(from: url)
        } catch {
            print("Import rejected - file is not a valid archive: \(error.localizedDescription)")
            return false
        }

        guard validate(objects).isValid else {
            print("Import rejected - archive failed validation")
            return false
        }

        createBackup(reason: "pre_import")

        do {
            try DataArchive.write(objects, to: dataURL)
            print("Data imported successfully - \(objects.count) records")
            saveDataVersion(recordCount: objects.count)
            return true
        } catch {
            print("Import failed: \(error.localizedDescription)")
            return false
        }
    }
}
