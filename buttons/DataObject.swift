//
//  File.swift
//  Pushup Hero
//
//  Created by Joshua Dance on 10/14/20.
//  Copyright © 2020 Joshua Dance. All rights reserved.
//

import Foundation

class DataObject: NSObject, NSSecureCoding {

    // MARK: - Data Version Tracking
    // Increment this when changing the data schema
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
        // Decode version (defaults to 0 for old data without version)
        let version = aDecoder.decodeInteger(forKey: Key.dataVersionKey)

        // Decode with backward compatibility
        // Use secure decoding for classes, with fallback for old NSCoding format
        var listOfStrings: [String] = []
        if let decodedStrings = aDecoder.decodeObject(of: [NSArray.self, NSString.self], forKey: Key.myStringKey) as? [String] {
            listOfStrings = decodedStrings
        } else {
            // Fallback for very old data
            listOfStrings = ["nothing saved yet"]
        }

        var dateOfSave = Date()
        if let decodedDate = aDecoder.decodeObject(of: NSDate.self, forKey: Key.myDateKey) as? Date {
            dateOfSave = decodedDate
        }

        var dateOfWorkout = Date()
        // Handle migration from old data that didn't have dateOfWorkout
        if let decodedWorkoutDate = aDecoder.decodeObject(of: NSDate.self, forKey: Key.myDateWorkoutKey) as? Date {
            dateOfWorkout = decodedWorkoutDate
        } else {
            // Backward compatibility: if dateOfWorkout doesn't exist, use dateOfSave
            dateOfWorkout = dateOfSave
        }

        let numberOfPushups = aDecoder.decodeInteger(forKey: Key.myNumberKey)

        self.init(argumentListOfStrings: listOfStrings, argumentDateOfSave: dateOfSave, argumentDateOfWorkout: dateOfWorkout, argumentNumberOfPushups: numberOfPushups)

        // Set the version
        self.dataVersion = version > 0 ? version : DataObject.currentDataVersion
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
