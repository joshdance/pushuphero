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


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Perform data migration and validation on app launch
        let migrationSuccess = DataMigrationManager.shared.performMigrationIfNeeded()

        if !migrationSuccess {
            // Data recovery failed - show alert to user
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showDataRecoveryAlert()
            }
        }

        return true
    }

    private func showDataRecoveryAlert() {
        guard let rootViewController = window?.rootViewController else { return }

        let alert = UIAlertController(
            title: "Data Recovery Issue",
            message: "We encountered an issue loading your workout data. Your data may have been recovered from a backup. Please verify your workout history.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        rootViewController.present(alert, animated: true, completion: nil)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Create automatic backup when app goes to background
        _ = DataMigrationManager.shared.createBackup(reason: "background")
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

