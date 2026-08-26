//
//  AppDelegate.swift
//  buttons
//
//  Created by Joshua Dance on 2/24/18.
//  Copyright © 2018 Joshua Dance. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    /// Set when the launch-time data check found something the user should know
    /// about. ViewController drains this in viewDidAppear, when there is
    /// actually a window to present into — presenting from didFinishLaunching
    /// races the root view controller and the alert is usually swallowed.
    static var pendingLaunchAlert: (title: String, message: String)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        let outcome = DataMigrationManager.shared.performMigrationIfNeeded()

        switch outcome {
        case .freshInstall, .ok:
            break

        case .upgradedFromLegacy(let count):
            print("Upgrade complete - \(count) workouts carried over")

        case .recovered(let source, let count):
            AppDelegate.pendingLaunchAlert = (
                "Workout History Restored",
                "Pushup Hero could not read your workout file, so it restored a backup from \(AppDelegate.describe(source)). \(count) workout\(count == 1 ? "" : "s") were recovered. Any workouts saved after that backup may be missing, and the original file has been kept."
            )

        case .historyShrank(let count, let previous):
            print("History shrank from \(previous) to \(count)")
            AppDelegate.pendingLaunchAlert = (
                "Some Workouts Are Missing",
                "Pushup Hero previously recorded \(previous) workouts but can now only find \(count). Nothing has been deleted and older backups are being kept, so please get in touch before this gets overwritten — tap the \"Pushup Hero\" title for diagnostics."
            )

        case .failed(let reason, let preservedAs):
            print("Data recovery failed: \(reason)")
            // Only claim the original was set aside when it actually was —
            // when the data file was simply missing, there was nothing to keep.
            let kept = preservedAs == nil
                ? "Nothing has been deleted."
                : "Nothing has been deleted — your original file has been kept."
            AppDelegate.pendingLaunchAlert = (
                "Workout History Unavailable",
                "Pushup Hero could not read your workout history and no usable backup was found. \(kept) Please contact support before saving new workouts if your history matters to you."
            )

        case .recoveryBlocked(let reason):
            print("Recovery blocked: \(reason)")
            // Distinct from .failed: backups were never consulted and nothing on
            // disk was touched, so telling the user "no backup was found" would
            // be false and might push them into deleting recoverable data.
            AppDelegate.pendingLaunchAlert = (
                "Not Enough Space to Load Safely",
                "Pushup Hero could not read your workout file, and could not set a copy of it aside before doing anything else. Nothing has been changed and your backups are untouched. Freeing up storage space and reopening the app should let it recover your history."
            )
        }

        return true
    }

    /// Turns a backup filename back into something worth showing a person.
    private static func describe(_ filename: String) -> String {
        let parts = filename.components(separatedBy: "_")
        guard let stamp = parts.last else { return "an earlier session" }

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS"
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = parser.date(from: stamp) else { return "an earlier session" }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Snapshot on the way out, but only if what is on disk is actually good.
        // Backing up unvalidated data would let a corrupt file occupy the
        // retention window and push out the last readable copies.
        guard DataMigrationManager.shared.validateDataFile().isValid else {
            print("Skipping background backup - current data did not validate")
            return
        }
        DataMigrationManager.shared.createBackup(reason: "background")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}
