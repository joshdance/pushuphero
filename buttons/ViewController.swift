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
var pushupNumber = 0
var popColor = #colorLiteral(red: 0.2588235294, green: 0.9607843137, blue: 0.6196078431, alpha: 1)
var borderColor = #colorLiteral(red: 0.7843137255, green: 0.7843137255, blue: 0.7843137255, alpha: 1)

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
    @IBOutlet weak var saveButton: UIButton!
    @IBOutlet weak var dailyBox: UIView!
    @IBOutlet weak var weeklyBox: UIView!
    @IBOutlet weak var monthlyBox: UIView!
    @IBOutlet weak var yearlyBox: UIView!
    
    var audioPlayer = AVAudioPlayer()
    
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
        
        setUpViews()
        
        calculatePushupCounts()

    }
    
    func setUpViews() {
        middleTextField.text = "Enter text here. Then save."

        upButton.layer.borderWidth = 2.0
        upButton.backgroundColor = popColor
        upButton.layer.borderColor = borderColor.cgColor
        upButton.layer.cornerRadius = 10.0
        
        downButton.layer.borderWidth = 2.0
        downButton.backgroundColor = popColor
        downButton.layer.borderColor = borderColor.cgColor
        downButton.layer.cornerRadius = 10.0
        
        saveButton.layer.borderWidth = 2.0
        saveButton.backgroundColor = popColor
        saveButton.layer.borderColor = borderColor.cgColor
        saveButton.layer.cornerRadius = 10.0
        
        dailyBox.layer.borderWidth = 2.0
        dailyBox.layer.borderColor = borderColor.cgColor
        dailyBox.layer.cornerRadius = 10.0
        
        weeklyBox.layer.borderWidth = 2.0
        weeklyBox.layer.borderColor = borderColor.cgColor
        weeklyBox.layer.cornerRadius = 10.0
        
        monthlyBox.layer.borderWidth = 2.0
        monthlyBox.layer.borderColor = borderColor.cgColor
        monthlyBox.layer.cornerRadius = 10.0
        
        yearlyBox.layer.borderWidth = 2.0
        yearlyBox.layer.borderColor = borderColor.cgColor
        yearlyBox.layer.cornerRadius = 10.0
    }
    
    func playSound(sound: String){
        let path = Bundle.main.path(forResource: sound, ofType: nil)!
        let url = URL(fileURLWithPath: path)
        
        let audioSession = AVAudioSession.sharedInstance()
        try!audioSession.setCategory(AVAudioSessionCategoryPlayback, with: AVAudioSessionCategoryOptions.duckOthers)
        
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
            holdTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(addChunkPushup), userInfo: nil, repeats: true)
        }
        if press.state == .cancelled || press.state == .ended {
            holdTimer.invalidate()
        }
    }
    
    @objc func downHold(press:UILongPressGestureRecognizer) {
        if press.state == .began {
            removeChunkPushup()
            holdTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(removeChunkPushup), userInfo: nil, repeats: true)
        }
        if press.state == .cancelled || press.state == .ended {
            holdTimer.invalidate()
        }
    }

    //func changeChunk - give it the + or -?

    @objc func addChunkPushup() {
        pushupNumber = pushupNumber + 10
        numberLabel.text = String(pushupNumber)
        playSound(sound: Sounds.upSound)
    }
    
    @objc func removeChunkPushup() {
        //if pushupNumber is less than = 9 or less than 9, set to 0
        if pushupNumber >= 9 {
            pushupNumber = pushupNumber - 10
        } else {
            pushupNumber = 0
        }
        numberLabel.text = String(pushupNumber)
        playSound(sound: Sounds.downSound)
    }
    
    func calculatePushupCounts() {
        let calendar = Calendar.current
        let today =  Date()
        
        let weekComponents = calendar.dateComponents([.weekOfYear], from: today)
        let monthComponents = calendar.dateComponents([.month], from: today)
        let yearComponents = calendar.dateComponents([.year], from: today)
        
        var todaysPushupNumber = 0
        var thisWeeksPushups = 0
        var thisMonthsPushups = 0
        var thisYearsPushups = 0

        for workout in myArray {
            //see if any of the entries = today
            if calendar.isDateInToday(workout.dateOfWorkout) == true
            {
                //add them up.
                todaysPushupNumber = todaysPushupNumber + workout.numberOfPushups
            }
            
            var workoutComponents = calendar.dateComponents([.weekOfYear], from: workout.dateOfWorkout)
            if weekComponents.weekOfYear == workoutComponents.weekOfYear
            {
                thisWeeksPushups = thisWeeksPushups + workout.numberOfPushups
            }
            
            workoutComponents = calendar.dateComponents([.month], from: workout.dateOfWorkout)
            
            if monthComponents.month == workoutComponents.month
            {
                //add them up.
                thisMonthsPushups = thisMonthsPushups + workout.numberOfPushups
            }
            
            workoutComponents = calendar.dateComponents([.year], from: workout.dateOfWorkout)
            
            if yearComponents.year == workoutComponents.year
            {
                //add them up.
                thisYearsPushups = thisYearsPushups + workout.numberOfPushups
            }
        } //end for workout
        
        pushupsTodayLabel.text = String(todaysPushupNumber)
        pushupsThisWeekLabel.text = String(thisWeeksPushups)
        pushupsThisMonthLabel.text = String(thisMonthsPushups)
        pushupsThisYearLabel.text = String(thisYearsPushups)
        
    }
    
    @IBAction func tappedSaveButton(_ sender: Any) {
        //add the saved Text to the array.
        let newDataObject = DataObject(argumentListOfStrings: [], argumentDateOfSave: Date(), argumentDateOfWorkout: Date(),  argumentNumberOfPushups: Int())
        
        if middleTextField.text != "Enter text here. Then save."
        {
            savedText = middleTextField.text!
        } else {
            savedText = ""
        }
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
        calculatePushupCounts()

        middleTextField.endEditing(true)
        playSound(sound: Sounds.saveSound)
    }
        
    @IBAction func tappedUpButton(_ sender: Any) {
        playSound(sound: Sounds.upSound)
        pushupNumber = pushupNumber + 1
        numberLabel.text = String(pushupNumber)
    }
    
    @IBAction func tappedDownButton(_ sender: Any) {
        playSound(sound: Sounds.downSound)
        if pushupNumber != 0 {
            pushupNumber = pushupNumber - 1
        }
        numberLabel.text = String(pushupNumber)
    }
    
    func loadData() {
        let manager = FileManager.default
        
        if manager.fileExists(atPath: filePath) {
            print("The file exists!")
            
            //if we can get data back, get our data.
            let ourData = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as! Array<DataObject>
            myArray = ourData
            
            print("count of myArray = ", myArray.count)
            
        } else {
            print("The file DOES NOT exist! Mournful trumpets sound...")
        }
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
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
