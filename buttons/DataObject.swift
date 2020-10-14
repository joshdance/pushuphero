//
//  File.swift
//  Pushup Hero
//
//  Created by Joshua Dance on 10/14/20.
//  Copyright © 2020 Joshua Dance. All rights reserved.
//

import Foundation

class DataObject: NSObject, NSCoding {
    
    //var savedString: String
    
    var listOfStrings: [String] = ["nothing saved yet"]
    var dateOfSave = Date()
    var numberOfPushups = 0
    var dateOfWorkout = Date()
    
    struct Key {
        static let myStringKey = "myStringKey"
        static let myDateKey = "myDateKey"
        static let myNumberKey = "myNumberKey"
        static let myDateWorkoutKey = "myDateWorkoutKey"
    }
    
    //encode objects
    func encode(with aCoder: NSCoder) {
        aCoder.encode(listOfStrings, forKey: Key.myStringKey)
        aCoder.encode(dateOfSave, forKey: Key.myDateKey)
        aCoder.encode(dateOfWorkout, forKey: Key.myDateWorkoutKey)
        aCoder.encode(numberOfPushups, forKey: Key.myNumberKey)
    }
    
    //decode objects
    required convenience init?(coder aDecoder: NSCoder) {
        let listOfStrings =   aDecoder.decodeObject(forKey: Key.myStringKey) as! Array<String>
        let dateOfSave =      aDecoder.decodeObject(forKey: Key.myDateKey) as! Date
        
        var dateOfWorkout = Date()
        //if key exists !=
        if aDecoder.decodeObject(forKey: Key.myDateWorkoutKey) != nil {
            dateOfWorkout =   aDecoder.decodeObject(forKey: Key.myDateWorkoutKey) as! Date
        } else {
            //if the key == nil
            dateOfWorkout = dateOfSave
        }
        
        let numberOfPushups = aDecoder.decodeInteger(forKey: Key.myNumberKey) as Int
        
        self.init(argumentListOfStrings: listOfStrings, argumentDateOfSave: dateOfSave, argumentDateOfWorkout: dateOfWorkout, argumentNumberOfPushups: numberOfPushups)
    }
    
    init(argumentListOfStrings: [String], argumentDateOfSave: Date, argumentDateOfWorkout: Date, argumentNumberOfPushups: Int) {
        self.listOfStrings = argumentListOfStrings
        self.dateOfSave = argumentDateOfSave
        self.dateOfWorkout = argumentDateOfWorkout
        self.numberOfPushups = argumentNumberOfPushups
        super.init()
    }
}
