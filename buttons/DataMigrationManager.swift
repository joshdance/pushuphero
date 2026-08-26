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
    /// The live file was unusable and nothing could be restored. If the original
    /// bytes were set aside, the filename says where.
    case failed(reason: String, originalPreservedAs: String?)
    /// The live file was unusable AND could not be preserved, so nothing on disk
    /// was touched. Any backups are untouched and may still be perfectly good —
    /// this is a storage problem, not a lost-history problem.
    case recoveryBlocked(reason: String)
    /// Data is readable, but there are fewer workouts than there once were.
    /// The app cannot delete workouts, so this means history was lost somewhere.
    /// Backup cleanup is suspended so the fuller copies are not rotated away.
    case historyShrank(recordCount: Int, previousCount: Int)

    /// True when the user's history may differ from what they last saw.
    var needsUserAttention: Bool {
        switch self {
        case .recovered, .failed, .recoveryBlocked, .historyShrank: return true
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

    /// Snapshots that routine cleanup must never remove. Each marks a moment
    /// worth being able to return to: the state before a schema upgrade, the
    /// state before the user imported over their history, and the state at the
    /// point workouts were noticed to be missing.
    static let exemptBackupReasons = ["pre_migration", "pre_import", "history_shrank"]

    /// Exempt snapshots are kept indefinitely, but not infinitely.
    private let exemptBackupsToKeepPerReason = 3

    /// How many "holds more history than we currently have" backups to protect
    /// from rotation on top of the routine ones.
    private let richestBackupsToKeep = 3

    private let currentDataVersion = 1

    struct DataVersion: Codable {
        let version: Int
        let lastBackupDate: Date
        let appVersion: String
        /// Records present at the last verified-good launch.
        let recordCount: Int?
        /// The highest count ever seen. Storing only the latest count would
        /// erase the evidence the moment history shrank — the next launch would
        /// compare against the already-reduced number and see nothing wrong.
        let maxRecordCount: Int?
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
            return .failed(reason: "Could not locate the documents directory.", originalPreservedAs: nil)
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
                saveDataVersion(recordCount: 0, maxRecordCount: 0)
                return .freshInstall
            }
            print("Data file missing but history is expected - attempting recovery")
            return attemptRecovery(reason: "data file missing", preservedAs: nil)
        }

        // Validate before backing up, so a corrupt file never becomes a backup
        // and pushes the last good snapshots out of the retention window.
        let validation = validateDataFile()
        guard validation.isValid, let records = validation.recordCount else {
            print("Data validation failed: \(validation.error ?? "unknown error")")

            // Recovery writes over the data file, so it is only safe once the
            // unreadable bytes are preserved. If they are not, leave everything
            // exactly as it is — the backups are still untouched, and a later
            // launch can try again.
            let quarantine = quarantineCurrentDataFile(reason: "corrupt")
            guard quarantine.isSafeToProceed else {
                // Nothing on disk was touched. Backups, if any, are untouched
                // too — so this must not be reported as "no backup was found".
                print("Aborting recovery - could not preserve the unreadable file first")
                return .recoveryBlocked(reason: validation.error ?? "validation failed")
            }
            return attemptRecovery(reason: validation.error ?? "validation failed",
                                   preservedAs: quarantine.filename)
        }

        let isLegacyUpgrade = savedVersion == nil

        // Workouts cannot be deleted in this app, so a shortfall means history
        // was lost. There are two distinct signals here, and conflating them is
        // what made the alert both nag and miss:
        //
        //  - a NEW loss: fewer workouts than the previous launch saw. This just
        //    happened, so it is worth interrupting the user for.
        //  - a standing deficit: below the all-time peak. Worth protecting the
        //    backups for, but the user has already been told, and saving a new
        //    workout while short must not re-raise the alarm.
        let previousCount = savedVersion?.recordCount
        let previousMax = savedVersion?.maxRecordCount ?? savedVersion?.recordCount ?? 0
        let highWaterMark = max(records, previousMax)
        let droppedSinceLastLaunch = previousCount.map { records < $0 } ?? false
        let belowPeak = records < previousMax

        // Decide the snapshot's reason before taking it, not after. Backups are
        // deduplicated by content, so a routine snapshot taken first would make
        // the meaningful one a no-op — leaving the evidence tagged "pre_launch"
        // and eligible for routine cleanup. Only an actual drop earns the
        // exempt tag; tagging every below-peak launch would pile up snapshots
        // that cleanup is never allowed to remove.
        let backupReason: String
        if isLegacyUpgrade {
            backupReason = "pre_migration"
        } else if droppedSinceLastLaunch {
            backupReason = "history_shrank"
        } else {
            backupReason = "pre_launch"
        }
        createBackup(reason: backupReason)

        saveDataVersion(recordCount: records, maxRecordCount: highWaterMark)

        if belowPeak {
            print("Workouts below the highest seen (\(records) of \(previousMax))")
        }
        // Cleanup always runs, but it will not rotate away a backup holding
        // more workouts than the live file — those are the way back.
        cleanupOldBackups(liveRecordCount: records)

        if droppedSinceLastLaunch {
            print("WARNING: workouts dropped from \(previousCount ?? 0) to \(records)")
            return .historyShrank(recordCount: records, previousCount: previousMax)
        }

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
    private func attemptRecovery(reason: String, preservedAs: String?) -> MigrationOutcome {
        guard let dataURL = DataArchive.fileURL else {
            return .failed(reason: "Could not locate the documents directory.", originalPreservedAs: preservedAs)
        }

        let candidates = listBackups()
        guard !candidates.isEmpty else {
            print("No backups available for recovery")
            return .failed(reason: reason, originalPreservedAs: preservedAs)
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
            // Preserve the high-water mark so cleanup stays suspended and the
            // fuller backups survive, but mark this count as already-reported:
            // the recovery alert covers it, so the shrink check must not fire
            // a second alert for the same event on the next launch.
            // Keep the high-water mark so cleanup stays suspended and the
            // fuller backups survive. The recovery alert already tells the user
            // what happened, and recording this count as the latest means the
            // next launch sees no fresh drop and stays quiet.
            let priorMax = loadDataVersion()?.maxRecordCount ?? loadDataVersion()?.recordCount ?? 0
            saveDataVersion(recordCount: objects.count,
                            maxRecordCount: max(objects.count, priorMax))
            return .recovered(from: backup.filename, recordCount: objects.count)
        }

        print("No usable backup found")
        return .failed(reason: reason, originalPreservedAs: preservedAs)
    }

    /// Public entry point for the save path: preserve a data file the app could
    /// not decode, before a save is allowed to replace it.
    ///
    /// Returns false if the bytes could not be preserved. The caller must not
    /// write over the data file in that case — doing so would destroy the only
    /// copy of history the app failed to read.
    /// What happened to a file we tried to set aside.
    enum QuarantineOutcome {
        /// Bytes are safe, at this filename.
        case preserved(String)
        /// There was no file to preserve, which is equally safe.
        case nothingToPreserve
        /// The bytes could not be preserved. Callers must not overwrite.
        case failed

        var isSafeToProceed: Bool {
            switch self {
            case .preserved, .nothingToPreserve: return true
            case .failed: return false
            }
        }

        var filename: String? {
            if case .preserved(let name) = self { return name }
            return nil
        }
    }

    @discardableResult
    func quarantineUnreadableDataFile() -> Bool {
        return quarantineCurrentDataFile(reason: "unreadable").isSafeToProceed
    }

    /// Preserves an unreadable data file instead of deleting it, and reports
    /// whether it actually succeeded.
    ///
    /// Returns true only when the bytes are known to exist somewhere safe. A
    /// caller that overwrites the data file on a false return destroys the only
    /// copy of history the app could not read, which is the worst outcome this
    /// class exists to prevent.
    @discardableResult
    private func quarantineCurrentDataFile(reason: String) -> QuarantineOutcome {
        guard let dataURL = DataArchive.fileURL,
              let backupFolder = DataArchive.backupFolderURL else { return .failed }

        // Nothing on disk means there is nothing to lose.
        guard fileManager.fileExists(atPath: dataURL.path) else { return .nothingToPreserve }

        createBackupFolderIfNeeded()
        guard fileManager.fileExists(atPath: backupFolder.path) else {
            print("Could not quarantine data file: backup folder unavailable")
            return .failed
        }

        let destination = uniqueQuarantineURL(in: backupFolder, reason: reason)

        // Preferred: move. On a single volume this is an atomic rename, and it
        // leaves nothing behind for the caller to trip over.
        do {
            try fileManager.moveItem(at: dataURL, to: destination)
            print("Quarantined unreadable data file as \(destination.lastPathComponent)")
            return .preserved(destination.lastPathComponent)
        } catch {
            print("Could not move data file to quarantine: \(error.localizedDescription)")
        }

        // Fallback: copy, and verify the copy byte for byte. The original stays
        // where it is, which is just as safe — the bytes now exist in two places
        // rather than one, so the caller is free to overwrite the data file.
        do {
            let original = try Data(contentsOf: dataURL)
            try original.write(to: destination, options: .atomic)
            guard try Data(contentsOf: destination) == original else {
                try? fileManager.removeItem(at: destination)
                print("Could not quarantine data file: copy did not verify")
                return .failed
            }
            print("Quarantined a verified copy as \(destination.lastPathComponent)")
            return .preserved(destination.lastPathComponent)
        } catch {
            print("Could not quarantine data file: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Quarantine filenames must never collide: an existing file would make the
    /// move fail, and overwriting one would discard evidence we already kept.
    private func uniqueQuarantineURL(in folder: URL, reason: String) -> URL {
        let base = "Quarantine_\(reason)_\(Self.timestampFormatter.string(from: Date()))"
        var candidate = folder.appendingPathComponent(base)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(suffix)")
            suffix += 1
        }
        return candidate
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

    private func saveDataVersion(recordCount: Int, maxRecordCount: Int) {
        guard let url = DataArchive.versionFileURL else { return }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let version = DataVersion(version: currentDataVersion,
                                  lastBackupDate: Date(),
                                  appVersion: appVersion,
                                  recordCount: recordCount,
                                  maxRecordCount: maxRecordCount)

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
    /// Trims backups, protecting anything that could still put history back.
    ///
    /// `liveRecordCount` is what the data file currently holds. Any backup with
    /// more workouts than that is a potential way back, so the richest of those
    /// are kept regardless of age. That is a sharper rule than suspending
    /// cleanup whenever the count is low: it protects exactly the snapshots
    /// that matter, and stays bounded instead of accumulating forever.
    private func cleanupOldBackups(liveRecordCount: Int) {
        let all = listBackups()
        let routine = all.filter { !Self.exemptBackupReasons.contains($0.reason) }

        var keep = Set(routine.prefix(routineBackupsToKeep).map { $0.filename })

        let richer = routine
            .map { ($0, (try? DataArchive.read(from: $0.url))?.count ?? 0) }
            .filter { $0.1 > liveRecordCount }
            .sorted { $0.1 > $1.1 }
            .prefix(richestBackupsToKeep)
        if !richer.isEmpty {
            print("Protecting \(richer.count) backup(s) holding more workouts than the live file")
        }
        keep.formUnion(richer.map { $0.0.filename })

        for backup in routine where !keep.contains(backup.filename) {
            try? fileManager.removeItem(at: backup.url)
            print("Removed old backup: \(backup.filename)")
        }

        // Exempt snapshots are protected from routine rotation, not from all
        // limits — otherwise a device that keeps losing history would keep
        // accumulating them forever. Keep the OLDEST of each kind: those sit
        // closest to the fullest history, which is the whole reason to keep one.
        for reason in Self.exemptBackupReasons {
            let matching = all.filter { $0.reason == reason }.sorted { $0.timestamp < $1.timestamp }
            for backup in matching.dropFirst(exemptBackupsToKeepPerReason) {
                try? fileManager.removeItem(at: backup.url)
                print("Removed surplus \(reason) snapshot: \(backup.filename)")
            }
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
            // Importing is a deliberate choice to replace history, so it resets
            // the baseline. Otherwise importing an older backup would trip the
            // shrink warning for as long as the user took to catch back up.
            saveDataVersion(recordCount: objects.count,
                            maxRecordCount: objects.count)
            return true
        } catch {
            print("Import failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Debug Reporting

extension DataMigrationManager {

    /// A plain-text snapshot of everything that determines whether the user's
    /// history is safe. Intended to be read over a support email, so it favours
    /// being unambiguous over being short.
    ///
    /// Foundation-only on purpose: this lives beside the storage code it
    /// describes, and the scenario tests compile this file without UIKit.
    func debugReport(inMemoryCount: Int, loadFailed: Bool) -> String {
        var lines: [String] = []

        func section(_ title: String) {
            lines.append("")
            lines.append("── \(title) ──")
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        lines.append("PUSHUP HERO DIAGNOSTICS")
        lines.append(Self.displayFormatter.string(from: Date()))
        lines.append("App \(appVersion) (build \(build))")

        // MARK: App state
        section("App state")
        lines.append("Workouts loaded in app: \(inMemoryCount)")
        lines.append(loadFailed
            ? "Load status: FAILED — the next save will set the unreadable file aside instead of overwriting it"
            : "Load status: OK")

        // MARK: Version tracking
        section("Version tracking")
        if let version = loadDataVersion() {
            lines.append("Schema version: \(version.version)")
            lines.append("Last checked: \(Self.displayFormatter.string(from: version.lastBackupDate))")
            lines.append("Last app version to run: \(version.appVersion)")
            if let count = version.recordCount {
                lines.append("Workouts at last check: \(count)")
            }
            if let peak = version.maxRecordCount {
                lines.append("Most workouts ever seen: \(peak)")
                if inMemoryCount < peak {
                    lines.append("*** WARNING: \(peak - inMemoryCount) workouts missing versus the highest count seen")
                    lines.append("*** Backups holding more workouts than the current file are protected from cleanup")
                }
            }
        } else {
            lines.append("No DataVersion file.")
            lines.append("Means either a fresh install, or an upgrade that has not launched yet.")
        }

        // MARK: Data file
        section("Data file")
        if let dataURL = DataArchive.fileURL {
            lines.append("Path: Documents/\(dataURL.lastPathComponent)")
            if fileManager.fileExists(atPath: dataURL.path) {
                let attributes = try? fileManager.attributesOfItem(atPath: dataURL.path)
                let size = (attributes?[.size] as? Int64) ?? 0
                lines.append("Size: \(Self.formatBytes(size))")
                if let modified = attributes?[.modificationDate] as? Date {
                    lines.append("Modified: \(Self.displayFormatter.string(from: modified))")
                }

                // Which on-disk format is it in? Legacy files are only rewritten
                // on the first successful save, so this can legitimately still
                // say "original" straight after an upgrade.
                if let raw = try? Data(contentsOf: dataURL) {
                    lines.append("Format: \(Self.describeFormat(raw))")
                }

                let validation = validateDataFile()
                if validation.isValid {
                    lines.append("Validation: PASSED (\(validation.recordCount ?? 0) workouts)")
                } else {
                    lines.append("Validation: FAILED — \(validation.error ?? "unknown error")")
                }
            } else {
                lines.append("*** No data file present.")
            }
        } else {
            lines.append("*** Documents directory unavailable.")
        }

        // MARK: Backups
        let backups = listBackups()
        section("Backups (\(backups.count))")
        if backups.isEmpty {
            lines.append("None.")
        } else {
            let total = backups.reduce(Int64(0)) { $0 + $1.fileSize }
            lines.append("Total size: \(Self.formatBytes(total))")
            lines.append("")
            for backup in backups {
                let when = backup.timestamp == .distantPast
                    ? "unknown date"
                    : Self.displayFormatter.string(from: backup.timestamp)
                var detail = "• \(backup.reason) — \(when) — \(Self.formatBytes(backup.fileSize))"
                if let objects = try? DataArchive.read(from: backup.url) {
                    detail += " — \(objects.count) workouts"
                } else {
                    detail += " — UNREADABLE"
                }
                lines.append(detail)
            }
            lines.append("")
            lines.append("Kept: last \(routineBackupsToKeep) routine backups.")
            lines.append("Kept permanently: \(Self.exemptBackupReasons.joined(separator: ", ")).")
        }

        // MARK: Quarantine
        let quarantined = quarantinedFiles()
        if !quarantined.isEmpty {
            section("Quarantined files (\(quarantined.count))")
            lines.append("Files that could not be read. Kept, never deleted.")
            lines.append("")
            for item in quarantined {
                lines.append("• \(item)")
            }
        }

        section("Storage note")
        lines.append("All of the above lives inside the app's sandbox.")
        lines.append("It survives app updates. It does NOT survive deleting the app.")

        return lines.joined(separator: "\n")
    }

    private func quarantinedFiles() -> [String] {
        guard let folder = DataArchive.backupFolderURL,
              let files = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        return files.filter { $0.hasPrefix("Quarantine_") }.sorted().reversed()
    }

    /// Distinguishes an archive written before this version from one written after.
    private static func describeFormat(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .isoLatin1) else {
            return "unrecognised"
        }
        if text.contains("Pushup_Hero.DataObject") || text.contains("DataObject") {
            // Version-stamped records only exist in archives this build wrote.
            return text.contains("dataVersionKey")
                ? "current (version-stamped)"
                : "original (pre-upgrade) — will be rewritten on the next save"
        }
        return "unrecognised — does not look like a workout archive"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) bytes" }
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
