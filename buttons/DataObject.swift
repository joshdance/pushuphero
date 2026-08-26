//
//  DataObject.swift
//  Pushup Hero
//
//  Created by Joshua Dance on 10/14/20.
//  Copyright © 2020 Joshua Dance. All rights reserved.
//

import Foundation

// The Objective-C runtime name is pinned so that archives are written with a
// stable class name. Without this, NSKeyedArchiver records the module-qualified
// name ("Pushup_Hero.DataObject"), which means renaming the target — or reading
// the file from the second target, whose module is "Pushup_Hero_copy" — makes
// every existing archive silently undecodable. See DataArchive.legacyClassNames.
@objc(DataObject)
class DataObject: NSObject, NSSecureCoding {

    // MARK: - Data Version Tracking
    // Increment this when changing the data schema.
    // Version 0 means "written by a build that predates version tracking".
    static let currentDataVersion = 1

    // MARK: - Properties
    var listOfStrings: [String] = ["nothing saved yet"]
    var dateOfSave = Date()
    var numberOfPushups = 0
    var dateOfWorkout = Date()
    var dataVersion = DataObject.currentDataVersion

    // MARK: - NSSecureCoding
    static var supportsSecureCoding: Bool {
        return true
    }

    struct Key {
        static let myStringKey = "myStringKey"
        static let myDateKey = "myDateKey"
        static let myNumberKey = "myNumberKey"
        static let myDateWorkoutKey = "myDateWorkoutKey"
        static let dataVersionKey = "dataVersionKey"
    }

    // MARK: - Encoding
    func encode(with aCoder: NSCoder) {
        aCoder.encode(listOfStrings, forKey: Key.myStringKey)
        aCoder.encode(dateOfSave, forKey: Key.myDateKey)
        aCoder.encode(dateOfWorkout, forKey: Key.myDateWorkoutKey)
        aCoder.encode(numberOfPushups, forKey: Key.myNumberKey)
        aCoder.encode(dataVersion, forKey: Key.dataVersionKey)
    }

    // MARK: - Decoding
    required convenience init?(coder aDecoder: NSCoder) {
        // A record must carry at least one of the fields that every historical
        // version wrote. If none are present we are not looking at a DataObject,
        // and returning nil lets the caller treat the file as corrupt rather
        // than silently manufacturing a plausible-looking empty workout.
        let hasRecognisableField = aDecoder.containsValue(forKey: Key.myNumberKey)
            || aDecoder.containsValue(forKey: Key.myDateKey)
            || aDecoder.containsValue(forKey: Key.myStringKey)
        guard hasRecognisableField else { return nil }

        // Absent version key means legacy data, which is version 0.
        let version = aDecoder.containsValue(forKey: Key.dataVersionKey)
            ? aDecoder.decodeInteger(forKey: Key.dataVersionKey)
            : 0

        var listOfStrings: [String] = []
        if let decodedStrings = aDecoder.decodeObject(of: [NSArray.self, NSString.self],
                                                      forKey: Key.myStringKey) as? [String] {
            listOfStrings = decodedStrings
        } else {
            listOfStrings = ["nothing saved yet"]
        }

        var dateOfSave = Date()
        if let decodedDate = aDecoder.decodeObject(of: NSDate.self, forKey: Key.myDateKey) as? Date {
            dateOfSave = decodedDate
        }

        // Builds before the workout-date feature only stored dateOfSave.
        var dateOfWorkout = dateOfSave
        if let decodedWorkoutDate = aDecoder.decodeObject(of: NSDate.self,
                                                          forKey: Key.myDateWorkoutKey) as? Date {
            dateOfWorkout = decodedWorkoutDate
        }

        let numberOfPushups = aDecoder.decodeInteger(forKey: Key.myNumberKey)

        self.init(argumentListOfStrings: listOfStrings,
                  argumentDateOfSave: dateOfSave,
                  argumentDateOfWorkout: dateOfWorkout,
                  argumentNumberOfPushups: numberOfPushups)

        // Preserve the version the record was actually written with. Stamping it
        // with currentDataVersion here would erase the only signal that this row
        // came from an older schema.
        self.dataVersion = version
    }

    // MARK: - Initialization
    init(argumentListOfStrings: [String], argumentDateOfSave: Date, argumentDateOfWorkout: Date, argumentNumberOfPushups: Int) {
        self.listOfStrings = argumentListOfStrings
        self.dateOfSave = argumentDateOfSave
        self.dateOfWorkout = argumentDateOfWorkout
        self.numberOfPushups = argumentNumberOfPushups
        self.dataVersion = DataObject.currentDataVersion
        super.init()
    }
}

// MARK: - DataArchive

enum DataArchiveError: LocalizedError {
    case empty
    case unreadable(Error)
    case malformed(Error?)
    case wrongRootType(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The data file is empty."
        case .unreadable(let error):
            return "The data file could not be read: \(error.localizedDescription)"
        case .malformed(let error):
            return "The data file is not a valid archive: \(error?.localizedDescription ?? "unknown format")"
        case .wrongRootType(let found):
            return "The data file contained \(found) instead of a list of workouts."
        }
    }
}

/// The single read/write path for the workout archive.
///
/// Everything that touches the on-disk file — the view controller and the
/// migration manager alike — goes through here. That matters more than it
/// looks: when validation and loading use different decoders they can disagree,
/// and a validator that wrongly reports "corrupt" causes recovery to replace
/// perfectly good data with an older backup.
enum DataArchive {

    // MARK: Locations

    private static var documentsURL: URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static var fileURL: URL? {
        return documentsURL?.appendingPathComponent("Data")
    }

    static var backupFolderURL: URL? {
        return documentsURL?.appendingPathComponent("Backups")
    }

    static var versionFileURL: URL? {
        return documentsURL?.appendingPathComponent("DataVersion")
    }

    /// Class names that historical builds may have written into archives.
    /// NSKeyedArchiver stores Swift classes module-qualified, so an archive
    /// written before `@objc(DataObject)` was added names the module. Mapping
    /// them all back to DataObject is what keeps old installs readable.
    private static let legacyClassNames = [
        "Pushup_Hero.DataObject",
        "Pushup_Hero_copy.DataObject",
        "buttons.DataObject",
        "DataObject"
    ]

    // MARK: Decoding

    static func decode(_ data: Data) throws -> [DataObject] {
        guard !data.isEmpty else { throw DataArchiveError.empty }

        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            throw DataArchiveError.malformed(error)
        }

        // Archives written by earlier builds used plain NSCoding, so secure
        // coding cannot be required on read or that history becomes unreadable.
        // The file lives in our own sandbox container, so it is not attacker
        // controlled. New writes still require secure coding — see encode().
        unarchiver.requiresSecureCoding = false
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        for name in legacyClassNames {
            unarchiver.setClass(DataObject.self, forClassName: name)
        }
        defer { unarchiver.finishDecoding() }

        let root: Any?
        do {
            root = try unarchiver.decodeTopLevelObject(
                of: [NSArray.self, DataObject.self, NSDate.self, NSString.self],
                forKey: NSKeyedArchiveRootObjectKey)
        } catch {
            throw DataArchiveError.malformed(error)
        }

        if let error = unarchiver.error {
            throw DataArchiveError.malformed(error)
        }

        guard let objects = root as? [DataObject] else {
            throw DataArchiveError.wrongRootType(root.map { String(describing: type(of: $0)) } ?? "nothing")
        }
        return objects
    }

    /// The class name written into new archives.
    ///
    /// This is deliberately the *old* module-qualified name rather than the
    /// pinned `DataObject`. Writing the bare name would make every new file
    /// unreadable by builds that predate `@objc(DataObject)` — and those builds
    /// force-unwrap the decode, so they crash on launch rather than failing
    /// gracefully. Keeping the historical name on write means an older build
    /// (a TestFlight rollback, say) can still open a file this version wrote.
    ///
    /// Renaming the target is still safe: reads map every name in
    /// `legacyClassNames` back to DataObject, and writes do not depend on the
    /// current module at all.
    private static let archivedClassName = "Pushup_Hero.DataObject"

    static func encode(_ objects: [DataObject]) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName(archivedClassName, for: DataObject.self)
        archiver.encode(objects, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    // MARK: File access

    static func read(from url: URL) throws -> [DataObject] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DataArchiveError.unreadable(error)
        }
        return try decode(data)
    }

    /// Writes atomically, so an interrupted save can never leave a half-written
    /// file where the complete previous one used to be.
    static func write(_ objects: [DataObject], to url: URL) throws {
        let data = try encode(objects)
        try data.write(to: url, options: .atomic)
    }
}
