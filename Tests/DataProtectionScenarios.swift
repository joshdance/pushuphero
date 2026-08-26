import Foundation

// ============ Test harness ============
var failures = 0
func check(_ label: String, _ cond: Bool, _ detail: String = "") {
    print("\(cond ? "  PASS" : "  FAIL") \(label)\(detail.isEmpty ? "" : "  [\(detail)]")")
    if !cond { failures += 1 }
}

let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
func resetWorld() {
    try? FileManager.default.removeItem(at: docs)
    try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
}

/// Writes an archive exactly the way the OLD shipping app did:
/// NSKeyedArchiver.archiveRootObject(_:toFile:) with a module-qualified class name.
func writeLegacyArchive(_ objects: [DataObject], moduleName: String) {
    let a = NSKeyedArchiver(requiringSecureCoding: false)
    a.setClassName("\(moduleName).DataObject", for: DataObject.self)
    a.encode(objects, forKey: NSKeyedArchiveRootObjectKey)
    a.finishEncoding()
    try! a.encodedData.write(to: DataArchive.fileURL!)
}

func makeWorkouts(_ counts: [Int]) -> [DataObject] {
    return counts.map {
        DataObject(argumentListOfStrings: ["set of \($0)"],
                   argumentDateOfSave: Date(timeIntervalSince1970: 1_600_000_000 + Double($0 * 86400)),
                   argumentDateOfWorkout: Date(timeIntervalSince1970: 1_600_000_000 + Double($0 * 86400)),
                   argumentNumberOfPushups: $0)
    }
}

func loadedCounts() -> [Int] {
    guard let objs = try? DataArchive.read(from: DataArchive.fileURL!) else { return [] }
    return objs.map { $0.numberOfPushups }
}

let mgr = DataMigrationManager.shared

// ---------------------------------------------------------------
print("\n[1] Upgrade from the OLD shipping app (legacy NSCoding archive, no DataVersion file)")
resetWorld()
writeLegacyArchive(makeWorkouts([10, 20, 30]), moduleName: "Pushup_Hero")
var outcome = mgr.performMigrationIfNeeded()
if case .upgradedFromLegacy(let n) = outcome {
    check("recognised as a legacy upgrade, not a fresh install", true, "\(n) records")
} else {
    check("recognised as a legacy upgrade, not a fresh install", false, "got \(outcome)")
}
check("all 3 legacy workouts readable", loadedCounts() == [10, 20, 30], "\(loadedCounts())")
check("pre-upgrade snapshot was taken", mgr.listBackups().contains { $0.reason == "pre_migration" },
      mgr.listBackups().map { $0.filename }.joined(separator: ","))

// ---------------------------------------------------------------
print("\n[2] Legacy archive written by the OTHER target's module name")
resetWorld()
writeLegacyArchive(makeWorkouts([7, 8]), moduleName: "Pushup_Hero_copy")
check("cross-module archive still decodes", loadedCounts() == [7, 8], "\(loadedCounts())")

// ---------------------------------------------------------------
print("\n[3] Modern round-trip preserves every field")
resetWorld()
let original = makeWorkouts([15])
try! DataArchive.write(original, to: DataArchive.fileURL!)
let back = try! DataArchive.read(from: DataArchive.fileURL!)
check("pushup count preserved", back[0].numberOfPushups == 15)
check("save date preserved", abs(back[0].dateOfSave.timeIntervalSince(original[0].dateOfSave)) < 0.001)
check("workout date preserved", abs(back[0].dateOfWorkout.timeIntervalSince(original[0].dateOfWorkout)) < 0.001)
check("label preserved", back[0].listOfStrings == ["set of 15"], "\(back[0].listOfStrings)")

// ---------------------------------------------------------------
print("\n[4] Validator agrees with the loader on a file the app just wrote")
resetWorld()
try! DataArchive.write(makeWorkouts([1, 2, 3, 4]), to: DataArchive.fileURL!)
let v = mgr.validateDataFile()
check("modern archive validates as intact", v.isValid, v.error ?? "")
check("record count correct", v.recordCount == 4, "\(v.recordCount ?? -1)")

// ---------------------------------------------------------------
print("\n[5] Corrupt data file: recovery from backup, original never deleted")
resetWorld()
try! DataArchive.write(makeWorkouts([100, 200]), to: DataArchive.fileURL!)
_ = mgr.performMigrationIfNeeded()                       // establishes a good backup
try! Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: DataArchive.fileURL!)   // corruption
outcome = mgr.performMigrationIfNeeded()
if case .recovered(_, let n) = outcome {
    check("recovered from backup", true, "\(n) records")
} else {
    check("recovered from backup", false, "got \(outcome)")
}
check("recovered workouts are the real ones", loadedCounts() == [100, 200], "\(loadedCounts())")
check("corrupt original was quarantined, not deleted",
      (try! FileManager.default.contentsOfDirectory(atPath: DataArchive.backupFolderURL!.path))
        .contains { $0.hasPrefix("Quarantine_") })

// ---------------------------------------------------------------
print("\n[6] Every backup is corrupt: must terminate, not recurse forever")
resetWorld()
try! FileManager.default.createDirectory(at: DataArchive.backupFolderURL!, withIntermediateDirectories: true)
for i in 1...6 {
    let name = "Data_pre_launch_2024-01-0\(i)T00-00-00-000"
    try! Data([0x00, 0x01]).write(to: DataArchive.backupFolderURL!.appendingPathComponent(name))
}
try! Data([0xDE, 0xAD]).write(to: DataArchive.fileURL!)
let started = Date()
outcome = mgr.performMigrationIfNeeded()
if case .failed = outcome {
    check("terminated with .failed instead of blowing the stack", true,
          String(format: "%.3fs", Date().timeIntervalSince(started)))
} else {
    check("terminated with .failed instead of blowing the stack", false, "got \(outcome)")
}

// ---------------------------------------------------------------
print("\n[7] Genuine fresh install")
resetWorld()
outcome = mgr.performMigrationIfNeeded()
if case .freshInstall = outcome { check("reported as fresh install", true) }
else { check("reported as fresh install", false, "got \(outcome)") }

// ---------------------------------------------------------------
print("\n[8] Repeated launches must not flush good backups out of retention")
resetWorld()
try! DataArchive.write(makeWorkouts([42]), to: DataArchive.fileURL!)
for _ in 1...12 { _ = mgr.performMigrationIfNeeded() }
let backups = mgr.listBackups()
check("identical relaunches did not create 12 redundant backups", backups.count <= 3, "\(backups.count) backups")
check("data still intact after 12 launches", loadedCounts() == [42], "\(loadedCounts())")

// ---------------------------------------------------------------
print("\n[9] Backups are ordered by real time, not filesystem creation date")
resetWorld()
try! FileManager.default.createDirectory(at: DataArchive.backupFolderURL!, withIntermediateDirectories: true)
try! DataArchive.write(makeWorkouts([1]), to: DataArchive.backupFolderURL!.appendingPathComponent("Data_pre_launch_2020-01-01T00-00-00-000"))
try! DataArchive.write(makeWorkouts([1, 2, 3]), to: DataArchive.backupFolderURL!.appendingPathComponent("Data_pre_launch_2025-06-01T00-00-00-000"))
check("newest backup is the 2025 one", mgr.listBackups().first?.filename.contains("2025") == true,
      mgr.listBackups().map { $0.filename }.joined(separator: " | "))

// ---------------------------------------------------------------
print("\n[10] Data file vanishes but backups exist -> recover, never call it a fresh install")
resetWorld()
try! DataArchive.write(makeWorkouts([5, 6, 7]), to: DataArchive.fileURL!)
_ = mgr.performMigrationIfNeeded()
try! FileManager.default.removeItem(at: DataArchive.fileURL!)
try? FileManager.default.removeItem(at: DataArchive.versionFileURL!)   // worst case: version file gone too
outcome = mgr.performMigrationIfNeeded()
if case .recovered(_, let n) = outcome { check("recovered rather than starting empty", true, "\(n) records") }
else { check("recovered rather than starting empty", false, "got \(outcome)") }
check("history restored", loadedCounts() == [5, 6, 7], "\(loadedCounts())")

// ---------------------------------------------------------------
print("\n[11] Garbage that is a VALID archive of the wrong type is rejected")
resetWorld()
try! NSKeyedArchiver.archivedData(withRootObject: ["not", "workouts"], requiringSecureCoding: true)
    .write(to: DataArchive.fileURL!)
check("wrong root type rejected by validator", !mgr.validateDataFile().isValid,
      mgr.validateDataFile().error ?? "")

// ---------------------------------------------------------------
print("\n[12] Empty and truncated files are rejected, not read as 'no workouts'")
resetWorld()
try! Data().write(to: DataArchive.fileURL!)
check("empty file rejected", !mgr.validateDataFile().isValid)
let full = try! DataArchive.encode(makeWorkouts([1, 2, 3, 4, 5]))
try! full.prefix(full.count / 2).write(to: DataArchive.fileURL!)
check("truncated file rejected", !mgr.validateDataFile().isValid)

print("\n================ \(failures == 0 ? "ALL SCENARIOS PASSED" : "\(failures) FAILURE(S)") ================")
exit(failures == 0 ? 0 : 1)
