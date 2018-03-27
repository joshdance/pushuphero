//
//  ViewController.swift
//  buttons
//
//  Created by Joshua Dance on 2/24/18.
//  Copyright © 2018 Joshua Dance. All rights reserved.
//

import UIKit
import AVFoundation

var myDataObject = DataObject(argumentListOfStrings: [], argumentDateOfSave: Date(), argumentDateOfWorkout: Date(), argumentNumberOfPushups: Int())
var savedText = ""
var formatter = DateFormatter()
var myArray:[DataObject] = []
var randomPushupNumber = 7
var pushupNumber = 0

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate {
    
    @IBOutlet weak var middleTextField: UITextField!
    @IBOutlet weak var numberLabel: UILabel!
    @IBOutlet weak var pushupTableView: UITableView!
    @IBOutlet weak var upButton: UIButton!
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var pushupsTodayLabel: UILabel!
    @IBOutlet weak var pushupsThisWeekLabel: UILabel!
    @IBOutlet weak var pushupsThisYearLabel: UILabel!
    @IBOutlet weak var pushupsThisMonthLabel: UILabel!
    
    var audioPlayer = AVAudioPlayer()
    
    struct Sounds {
        static let startupSound: String = "oblivion.wav"
        static let downSound: String = "shorttap.aif"
        static let upSound: String = "hollowtap.aif"
        static let saveSound: String = "upward.wav"
    }
    
    var holdTimer: Timer!
    
    var filePath: String {
        //manager lets you examine contents of a files and folders i your app.
        let manager = FileManager.default
        
        //returns an array of urls from our documentDirectory and we take the first
        let url = manager.urls(for: .documentDirectory, in: .userDomainMask).first
        //print("this is the url path in the document directory \(String(describing: url))")
        
        //creates a new path component and creates a new file called "Data" where we store our data array
        return(url!.appendingPathComponent("Data").path)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadData()
        playSound(sound: Sounds.startupSound)
        middleTextField.text = "Enter text here. Then save."
        
        pushupTableView.dataSource = self
        pushupTableView.delegate = self
        middleTextField.delegate = self
        
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(upHold(press:)))
        longPressRecognizer.minimumPressDuration = 0.3
        longPressRecognizer.delegate = self
        self.upButton.addGestureRecognizer(longPressRecognizer)
        
        let downLongPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(downHold(press:)))
        downLongPressRecognizer.minimumPressDuration = 0.3
        downLongPressRecognizer.delegate = self
        self.downButton.addGestureRecognizer(downLongPressRecognizer)
        
        calculatePushupsToday()
    }
    
    func playSound(sound: String){
        let path = Bundle.main.path(forResource: sound, ofType: nil)!
        let url = URL(fileURLWithPath: path)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.play()
        } catch {
            print("couldn't load the file")
        }
    }
    
    @objc func upHold(press:UILongPressGestureRecognizer) {
        if press.state == .began {
            addChunkPushup()
            holdTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(addChunkPushup), userInfo: nil, repeats: true)
        }
        if press.state == .cancelled || press.state == .ended {
            holdTimer.invalidate()
        }
    }
    
    @objc func downHold(press:UILongPressGestureRecognizer) {
        if press.state == .began {
            removeChunkPushup()
            holdTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(removeChunkPushup), userInfo: nil, repeats: true)
        }
        if press.state == .cancelled || press.state == .ended {
            holdTimer.invalidate()
        }
    }

    //func changeChunk - give it the + or -?
    
    @objc func addChunkPushup() {
        view.backgroundColor = UIColor.yellow
        pushupNumber = pushupNumber + 10
        numberLabel.text = String(pushupNumber)
    }
    
    @objc func removeChunkPushup() {
        view.backgroundColor = UIColor.red
        pushupNumber = pushupNumber - 10
        numberLabel.text = String(pushupNumber)
    }
    
    func calculatePushupsToday() {
        //get todays date
        calcPushupsThisWeek()
        calcPushupsThisMonth()
        calcPushupsThisYear()
        let calendar = Calendar.current
        var todaysPushupNumber = 0
        for workout in myArray {
            //see if any of the entries = today
            if calendar.isDateInToday(workout.dateOfWorkout) == true
            {
                //add them up.
                todaysPushupNumber = todaysPushupNumber + workout.numberOfPushups
            }
        } //end for workout
        let todaysPushupLabelText : String = String(todaysPushupNumber) + " pushups today"
        pushupsTodayLabel.text = todaysPushupLabelText
    } //end calculatePushupsToday
    
    func calcPushupsThisWeek(){
        let calendar = Calendar.current
        var thisWeeksPushups = 0
        let today =  Date()
        let todayComponents = calendar.dateComponents([.weekOfYear], from: today)
        
        for workout in myArray {
            let workoutComponents = calendar.dateComponents([.weekOfYear], from: workout.dateOfWorkout)
            if todayComponents.weekOfYear == workoutComponents.weekOfYear
            {
                thisWeeksPushups = thisWeeksPushups + workout.numberOfPushups
            }
        } //end for workout
        
        let weeksPushupLabelText : String = String(thisWeeksPushups) + " pushups this week"
        pushupsThisWeekLabel.text = weeksPushupLabelText
    }
    
    func calcPushupsThisMonth(){
        let calendar = Calendar.current
        var thisMonthsPushups = 0
        let today =  Date()
        let todayComponents = calendar.dateComponents([.month], from: today)
        
        for workout in myArray {
            //see if any of the entries = today
            
            let workoutComponents = calendar.dateComponents([.month], from: workout.dateOfWorkout)
            
            if todayComponents.month == workoutComponents.month
            {
                //add them up.
                thisMonthsPushups = thisMonthsPushups + workout.numberOfPushups
            }
        } //end for workout
        
        let monthPushupLabelText : String = String(thisMonthsPushups) + " pushups this month"
        pushupsThisMonthLabel.text = monthPushupLabelText
    }
    
    func calcPushupsThisYear(){
        let calendar = Calendar.current
        var thisYearsPushups = 0
        let today =  Date()
        let todayComponents = calendar.dateComponents([.year], from: today)
        
        for workout in myArray {
            //see if any of the entries = today
            
            let workoutComponents = calendar.dateComponents([.year], from: workout.dateOfWorkout)
            
            if todayComponents.year == workoutComponents.year
            {
                //add them up.
                thisYearsPushups = thisYearsPushups + workout.numberOfPushups
            }
        } //end for workout
        
        let yearsPushupLabelText : String = String(thisYearsPushups) + " pushups this year"
        pushupsThisYearLabel.text = yearsPushupLabelText
    }
    
    @IBAction func tappedSaveButton(_ sender: Any) {
        view.backgroundColor = UIColor.blue
        
        //add the saved Text to the array.
        let newDataObject = DataObject(argumentListOfStrings: [], argumentDateOfSave: Date(), argumentDateOfWorkout: Date(),  argumentNumberOfPushups: Int())
        
        savedText = middleTextField.text!
        newDataObject.listOfStrings.append(savedText)
        newDataObject.numberOfPushups = pushupNumber
        newDataObject.dateOfSave = Date()
        
        let calendar = Calendar.current
        let now = Date()
        let nowDateValue = now as Date
        let midnightToday = calendar.date(bySettingHour: 0, minute: 0, second: 1, of: now)
        let threeAMToday = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: now)
        
        //if 1 == 1
        if nowDateValue >= midnightToday! &&
            nowDateValue <= threeAMToday!
        {
            //date in range. Ask which day to apply
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            let dayName = formatter.string(from: now)
            
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
            let previousDayName = formatter.string(from: yesterday!)
            
            let messageString = "It is barely the next day. Do you want this workout to count for " + previousDayName + " or " + dayName + "?"
            
            let alert = UIAlertController(title: "Which day?", message: messageString, preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: previousDayName, style: .default, handler: { action in
                print(now)
                print(yesterday!)
                
                //let unitFlags: NSCalendarUnit = [.Hour, .Day, .Month, .Year]
                //make a set of calendar components
                var components = calendar.dateComponents([.hour, .minute, .day, .month, .year], from: yesterday!)
                
                components.hour = 23
                
                let yesterdayAlteredDate = calendar.date(from: components)
                
                //let yesterdayAlteredDate = calendar.date(bySetting: .hour, value: 1, of: yesterday!)
                print(yesterdayAlteredDate!)
                
                newDataObject.dateOfWorkout = yesterdayAlteredDate!
                self.save(newDataObject: newDataObject)
            }))
            alert.addAction(UIAlertAction(title: dayName, style: .default, handler: { action in
                newDataObject.dateOfWorkout = newDataObject.dateOfSave
                self.save(newDataObject: newDataObject)
            }))
            
            self.present(alert, animated: true)
            
        } else {
            newDataObject.dateOfWorkout = newDataObject.dateOfSave //normal case
            save(newDataObject: newDataObject)
        }
    }
    
    func save(newDataObject: DataObject) {
        myArray.insert(newDataObject, at: 0)
        NSKeyedArchiver.archiveRootObject(myArray, toFile: filePath)
        pushupTableView.reloadData()
        pushupNumber = 0
        numberLabel.text = String(pushupNumber)
        calculatePushupsToday()
        middleTextField.endEditing(true)
        playSound(sound: Sounds.saveSound)
    }
    
    @IBAction func tappedLoadButton(_ sender: Any) {
        view.backgroundColor = UIColor.green
        loadData()
        
        formatter.dateFormat = "MMM d yyyy, h:mm:ss a"
        let formattedDate = formatter.string(from: (myArray.last!.dateOfSave))
        
        pushupTableView.reloadData()
    }
    
    @IBAction func tappedUpButton(_ sender: Any) {
        view.backgroundColor = UIColor.green
        playSound(sound: Sounds.upSound)
        pushupNumber = pushupNumber + 1
        numberLabel.text = String(pushupNumber)
    }
    
    @IBAction func tappedDownButton(_ sender: Any) {
        view.backgroundColor = UIColor.orange
        playSound(sound: Sounds.downSound)
        pushupNumber = pushupNumber - 1
        numberLabel.text = String(pushupNumber)
    }
    
    func loadData() {
        //if we can get data back, get our data.
        let ourData = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as! Array<DataObject>
        myArray = ourData
        
        print("count of myArray = ", myArray.count)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let workout = myArray[indexPath.row]
        let cell: pushupCell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! pushupCell
        
        cell.pushupLabel.text = String(workout.numberOfPushups)
        
        formatter.dateFormat = "MMM d yyyy, h:mm a"
        let formattedDate = formatter.string(from: (workout.dateOfWorkout))
        cell.dateLabel.text = formattedDate

        cell.nameLabel.text = workout.listOfStrings.last
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return myArray.count
    }
    
    func textFieldDidBeginEditing(_ middleTextField: UITextField) {
        middleTextField.text = ""
    }
}

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

