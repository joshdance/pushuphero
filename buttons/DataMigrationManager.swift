//
//  DataMigrationManager.swift
//  Pushup Hero
//
//  Data Migration and Backup Manager
//  Protects user data during app upgrades
//

import Foundation

class DataMigrationManager {

    static let shared = DataMigrationManager()

    // MARK: - File Paths

    private let fileManager = FileManager.default

    private var dataFilePath: String {
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        return url!.appendingPathComponent("Data").path
    }

    private var backupFolderPath: String {
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        return url!.appendingPathComponent("Backups").path
    }

    private var versionFilePath: String {
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        return url!.appendingPathComponent("DataVersion").path
    }

    // MARK: - Version Tracking

    private let currentDataVersion = 1

    struct DataVersion: Codable {
        let version: Int
        let lastBackupDate: Date
        let appVersion: String
    }

    // MARK: - Public Interface

    /// Performs all necessary migration steps when app launches
    /// Returns true if migration was successful, false if data recovery is needed
    func performMigrationIfNeeded() -> Bool {
        // Create backup folder if it doesn't exist
        createBackupFolderIfNeeded()

        // Check if this is a fresh install or upgrade
        let savedVersion = loadDataVersion()
        let isFirstLaunch = savedVersion == nil

        if isFirstLaunch {
            print("📱 First launch detected - initializing data version tracking")
            saveDataVersion()
            return true
        }

        // Check if data file exists
        guard fileManager.fileExists(atPath: dataFilePath) else {
            print("⚠️ Data file not found - attempting recovery")
            return attemptDataRecovery()
        }

        // Create automatic backup before any operations
        let backupSuccess = createBackup(reason: "pre_launch")
        if !backupSuccess {
            print("⚠️ Warning: Backup creation failed")
        }

        // Validate data integrity
        let validationResult = validateDataFile()
        if !validationResult.isValid {
            print("⚠️ Data validation failed: \(validationResult.error ?? "unknown error")")
            return attemptDataRecovery()
        }

        // Update version tracking
        saveDataVersion()

        // Clean up old backups (keep last 5)
        cleanupOldBackups(keepLast: 5)

        print("✅ Data migration check complete - all data intact")
        return true
    }

    // MARK: - Backup Management

    /// Creates a backup of the current data file
    /// Returns true if successful
    func createBackup(reason: String = "manual") -> Bool {
        guard fileManager.fileExists(atPath: dataFilePath) else {
            print("⚠️ Cannot create backup - no data file exists")
            return false
        }

        createBackupFolderIfNeeded()

        // Create timestamped backup filename
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupFileName = "Data_\(reason)_\(timestamp)"
        let backupPath = (backupFolderPath as NSString).appendingPathComponent(backupFileName)

        do {
            try fileManager.copyItem(atPath: dataFilePath, toPath: backupPath)
            print("✅ Backup created: \(backupFileName)")
            return true
        } catch {
            print("❌ Backup failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Lists all available backups
    func listBackups() -> [BackupInfo] {
        guard fileManager.fileExists(atPath: backupFolderPath) else {
            return []
        }

        do {
            let files = try fileManager.contentsOfDirectory(atPath: backupFolderPath)
            let backups = files.compactMap { filename -> BackupInfo? in
                let fullPath = (backupFolderPath as NSString).appendingPathComponent(filename)
                guard let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
                      let creationDate = attributes[.creationDate] as? Date,
                      let fileSize = attributes[.size] as? Int64 else {
                    return nil
                }
                return BackupInfo(filename: filename, creationDate: creationDate, fileSize: fileSize)
            }
            return backups.sorted { $0.creationDate > $1.creationDate }
        } catch {
            print("❌ Failed to list backups: \(error.localizedDescription)")
            return []
        }
    }

    struct BackupInfo {
        let filename: String
        let creationDate: Date
        let fileSize: Int64
    }

    // MARK: - Data Recovery

    /// Attempts to recover data from the most recent backup
    func attemptDataRecovery() -> Bool {
        let backups = listBackups()

        guard let mostRecentBackup = backups.first else {
            print("❌ No backups available for recovery")
            return false
        }

        print("🔄 Attempting recovery from: \(mostRecentBackup.filename)")

        let backupPath = (backupFolderPath as NSString).appendingPathComponent(mostRecentBackup.filename)

        do {
            // Remove corrupted file if it exists
            if fileManager.fileExists(atPath: dataFilePath) {
                try fileManager.removeItem(atPath: dataFilePath)
            }

            // Restore from backup
            try fileManager.copyItem(atPath: backupPath, toPath: dataFilePath)

            // Validate recovered data
            let validation = validateDataFile()
            if validation.isValid {
                print("✅ Data successfully recovered from backup")
                return true
            } else {
                print("⚠️ Recovered data failed validation: \(validation.error ?? "unknown")")
                return tryNextBackup(excluding: mostRecentBackup.filename)
            }
        } catch {
            print("❌ Recovery failed: \(error.localizedDescription)")
            return tryNextBackup(excluding: mostRecentBackup.filename)
        }
    }

    private func tryNextBackup(excluding: String) -> Bool {
        let backups = listBackups().filter { $0.filename != excluding }

        guard let nextBackup = backups.first else {
            print("❌ No more backups to try")
            return false
        }

        print("🔄 Trying older backup: \(nextBackup.filename)")

        let backupPath = (backupFolderPath as NSString).appendingPathComponent(nextBackup.filename)

        do {
            if fileManager.fileExists(atPath: dataFilePath) {
                try fileManager.removeItem(atPath: dataFilePath)
            }
            try fileManager.copyItem(atPath: backupPath, toPath: dataFilePath)

            let validation = validateDataFile()
            if validation.isValid {
                print("✅ Data recovered from older backup")
                return true
            } else {
                return tryNextBackup(excluding: nextBackup.filename)
            }
        } catch {
            return tryNextBackup(excluding: nextBackup.filename)
        }
    }

    // MARK: - Data Validation

    struct ValidationResult {
        let isValid: Bool
        let error: String?
        let recordCount: Int?
    }

    /// Validates the integrity of the data file
    func validateDataFile() -> ValidationResult {
        guard fileManager.fileExists(atPath: dataFilePath) else {
            return ValidationResult(isValid: false, error: "File does not exist", recordCount: nil)
        }

        // Check if file is readable
        guard fileManager.isReadableFile(atPath: dataFilePath) else {
            return ValidationResult(isValid: false, error: "File is not readable", recordCount: nil)
        }

        // Try to unarchive the data
        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: dataFilePath) as? [DataObject] else {
            return ValidationResult(isValid: false, error: "Unable to unarchive data", recordCount: nil)
        }

        // Validate data structure
        for (index, object) in data.enumerated() {
            // Check for valid pushup count
            if object.numberOfPushups < 0 {
                return ValidationResult(isValid: false, error: "Invalid pushup count at index \(index)", recordCount: data.count)
            }

            // Check for valid dates
            if object.dateOfSave.timeIntervalSince1970 < 0 {
                return ValidationResult(isValid: false, error: "Invalid date at index \(index)", recordCount: data.count)
            }
        }

        print("✅ Data validation passed - \(data.count) records")
        return ValidationResult(isValid: true, error: nil, recordCount: data.count)
    }

    // MARK: - Version Management

    private func loadDataVersion() -> DataVersion? {
        guard fileManager.fileExists(atPath: versionFilePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: versionFilePath)),
              let version = try? JSONDecoder().decode(DataVersion.self, from: data) else {
            return nil
        }
        return version
    }

    private func saveDataVersion() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let version = DataVersion(version: currentDataVersion, lastBackupDate: Date(), appVersion: appVersion)

        if let data = try? JSONEncoder().encode(version) {
            try? data.write(to: URL(fileURLWithPath: versionFilePath))
        }
    }

    // MARK: - Helper Methods

    private func createBackupFolderIfNeeded() {
        if !fileManager.fileExists(atPath: backupFolderPath) {
            try? fileManager.createDirectory(atPath: backupFolderPath, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func cleanupOldBackups(keepLast: Int) {
        let backups = listBackups()

        guard backups.count > keepLast else { return }

        let backupsToDelete = Array(backups.dropFirst(keepLast))

        for backup in backupsToDelete {
            let fullPath = (backupFolderPath as NSString).appendingPathComponent(backup.filename)
            try? fileManager.removeItem(atPath: fullPath)
            print("🗑 Removed old backup: \(backup.filename)")
        }
    }

    // MARK: - Manual Operations

    /// Exports all data to a user-accessible location for manual backup
    func exportDataForBackup(to url: URL) -> Bool {
        guard fileManager.fileExists(atPath: dataFilePath) else {
            return false
        }

        do {
            let sourceURL = URL(fileURLWithPath: dataFilePath)
            try fileManager.copyItem(at: sourceURL, to: url)
            print("✅ Data exported successfully")
            return true
        } catch {
            print("❌ Export failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Imports data from a user-provided backup file
    func importDataFromBackup(from url: URL) -> Bool {
        // Create safety backup of current data first
        if fileManager.fileExists(atPath: dataFilePath) {
            _ = createBackup(reason: "pre_import")
        }

        do {
            // Copy imported file to data location
            let destinationURL = URL(fileURLWithPath: dataFilePath)

            // Remove existing file if present
            if fileManager.fileExists(atPath: dataFilePath) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: url, to: destinationURL)

            // Validate imported data
            let validation = validateDataFile()
            if validation.isValid {
                print("✅ Data imported successfully - \(validation.recordCount ?? 0) records")
                return true
            } else {
                print("❌ Imported data is invalid - restoring previous data")
                // Attempt to restore from pre-import backup
                return attemptDataRecovery()
            }
        } catch {
            print("❌ Import failed: \(error.localizedDescription)")
            return false
        }
    }
}
