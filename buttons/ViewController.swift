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
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var dailyBox: UIView!
    @IBOutlet weak var weeklyBox: UIView!
    @IBOutlet weak var monthlyBox: UIView!
    @IBOutlet weak var yearlyBox: UIView!
    
    var audioPlayer = AVAudioPlayer()
    
    var holdTimer: Timer!

    /// True when the on-disk history existed but could not be decoded. While set,
    /// the next save quarantines the original file instead of overwriting it.
    var loadFailed = false

    /// Alert queued from viewDidLoad, shown once the view is on screen.
    var pendingAlert: (title: String, message: String)?

    /// Tap-outside recognizer so the table and buttons can still receive the same touch.
    var dismissKeyboardTap: UITapGestureRecognizer!

    var keyboardDoneBar: KeyboardDoneAccessory!
    var keyboardDoneButton: UIButton!
    var keyboardSaveButton: UIButton!

    /// How far the text field is currently shifted to stay above the keyboard.
    var keyboardLift: CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadData()
        playSound(sound: Sounds.startupSound)
        
        configureKeyboardDismissal()
        configureKeyboardLift()
        
        pushupTableView.dataSource = self
        pushupTableView.delegate = self
        middleTextField.delegate = self

        let setLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSetLongPress(_:)))
        setLongPress.delegate = self
        pushupTableView.addGestureRecognizer(setLongPress)
        
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(upHold(press:)))
        longPressRecognizer.minimumPressDuration = 0.3
        longPressRecognizer.delegate = self
        self.upButton.addGestureRecognizer(longPressRecognizer)
        
        let downLongPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(downHold(press:)))
        downLongPressRecognizer.minimumPressDuration = 0.3
        downLongPressRecognizer.delegate = self
        self.downButton.addGestureRecognizer(downLongPressRecognizer)
        
        // Tapping the title opens lifetime stats. A three-finger tap on that
        // screen still opens diagnostics for support.
        titleLabel.isUserInteractionEnabled = true
        let statsTap = UITapGestureRecognizer(target: self, action: #selector(showStats))
        titleLabel.addGestureRecognizer(statsTap)
        
        setUpViews()
        
        calculatePushupCounts()

    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 13.0, *) {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                applyInterfaceColors()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Surface anything that went wrong during load or launch-time migration
        // now that there is a window to present into.
        if let launchAlert = AppDelegate.pendingLaunchAlert {
            AppDelegate.pendingLaunchAlert = nil
            pendingAlert = launchAlert
        }
        presentPendingAlertIfNeeded()
    }
    
    /// Dismisses the keyboard when tapping outside the field, and adds a left-side
    /// Done button on the accessory bar above the keyboard.
    func configureKeyboardDismissal() {
        dismissKeyboardTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissKeyboardTap.cancelsTouchesInView = false
        dismissKeyboardTap.delegate = self
        view.addGestureRecognizer(dismissKeyboardTap)

        let barHeight: CGFloat = 48
        let bar = KeyboardDoneAccessory(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: barHeight))
        bar.autoresizingMask = [.flexibleWidth]
        bar.isUserInteractionEnabled = true

        let doneButton = UIButton(type: .custom)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        doneButton.layer.cornerRadius = 8
        doneButton.layer.borderWidth = 2.0
        doneButton.clipsToBounds = true
        doneButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)

        let saveKeyboardButton = UIButton(type: .custom)
        saveKeyboardButton.setTitle("Save", for: .normal)
        saveKeyboardButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        saveKeyboardButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        saveKeyboardButton.layer.cornerRadius = 8
        saveKeyboardButton.layer.borderWidth = 2.0
        saveKeyboardButton.clipsToBounds = true
        saveKeyboardButton.addTarget(self, action: #selector(tappedSaveButton(_:)), for: .touchUpInside)

        bar.addSubview(doneButton)
        bar.addSubview(saveKeyboardButton)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        saveKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            doneButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            doneButton.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            doneButton.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
            doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            saveKeyboardButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            saveKeyboardButton.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            saveKeyboardButton.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
            saveKeyboardButton.leadingAnchor.constraint(greaterThanOrEqualTo: doneButton.trailingAnchor, constant: 12)
        ])

        keyboardDoneBar = bar
        keyboardDoneButton = doneButton
        keyboardSaveButton = saveKeyboardButton
        middleTextField.inputAccessoryView = bar
    }

    func configureKeyboardLift() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardFrameWillChange(_:)),
                                               name: NSNotification.Name.UIKeyboardWillChangeFrame,
                                               object: nil)
    }

    @objc func keyboardFrameWillChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let endFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }

        let duration = (userInfo[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (userInfo[UIKeyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let options = UIViewAnimationOptions(rawValue: curveRaw << 16).union(.beginFromCurrentState)

        let keyboardInView = view.convert(endFrame, from: nil)
        let dockTop = min(keyboardInView.minY, view.bounds.height)

        // convert() includes the current transform; add keyboardLift back to get
        // the resting position the constraints actually laid out.
        let fieldMaxY = middleTextField.convert(middleTextField.bounds, to: view).maxY + keyboardLift
        let lift = max(0, fieldMaxY - dockTop)
        keyboardLift = lift

        saveButton.superview?.transform = .identity
        view.bringSubview(toFront: middleTextField)

        UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
            self.middleTextField.transform = CGAffineTransform(translationX: 0, y: -lift)
            self.styleTextFieldForKeyboard(floating: lift > 0)
        }, completion: nil)
    }

    /// Rounded-rect fields don't fill a tall frame, which left a dark strip above
    /// the accessory. When floating, fill the frame and square the bottom edge
    /// so it meets the Done/Save bar.
    func styleTextFieldForKeyboard(floating: Bool) {
        if floating {
            middleTextField.borderStyle = .none
            middleTextField.clipsToBounds = true
            middleTextField.layer.cornerRadius = 10
            if #available(iOS 11.0, *) {
                middleTextField.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            }
        } else {
            middleTextField.borderStyle = .roundedRect
            middleTextField.clipsToBounds = false
            middleTextField.layer.cornerRadius = 0
            if #available(iOS 11.0, *) {
                middleTextField.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                                       .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        }
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer == dismissKeyboardTap {
            if let touchedView = touch.view, touchedView.isDescendant(of: middleTextField) {
                return false
            }
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer == dismissKeyboardTap || otherGestureRecognizer == dismissKeyboardTap
    }

    func setUpViews() {
        middleTextField.placeholder = "Enter text here. Then save."

        upButton.layer.borderWidth = 2.0
        upButton.backgroundColor = popColor
        upButton.layer.cornerRadius = 10.0
        
        downButton.layer.borderWidth = 2.0
        downButton.backgroundColor = popColor
        downButton.layer.cornerRadius = 10.0
        
        saveButton.layer.borderWidth = 2.0
        saveButton.backgroundColor = popColor
        saveButton.layer.cornerRadius = 10.0
        
        dailyBox.layer.borderWidth = 2.0
        dailyBox.layer.cornerRadius = 10.0
        
        weeklyBox.layer.borderWidth = 2.0
        weeklyBox.layer.cornerRadius = 10.0
        
        monthlyBox.layer.borderWidth = 2.0
        monthlyBox.layer.cornerRadius = 10.0
        
        yearlyBox.layer.borderWidth = 2.0
        yearlyBox.layer.cornerRadius = 10.0

        applyInterfaceColors()
    }

    /// Storyboard still uses static white fills. Labels use the dynamic label
    /// color, so dark mode painted white numbers on white cards. Colors that
    /// resolve to CGColor (borders) also have to be reapplied when the style
    /// changes, because a CGColor is a snapshot, not a dynamic color.
    func applyInterfaceColors() {
        let background: UIColor
        let card: UIColor
        let border: UIColor
        let fieldText: UIColor
        let placeholder: UIColor

        if #available(iOS 13.0, *) {
            background = .systemBackground
            card = .secondarySystemBackground
            border = .separator
            fieldText = .label
            // System placeholderText is too dim on a dark field. Keep it
            // secondary to typed text, but light enough to read at a glance.
            if traitCollection.userInterfaceStyle == .dark {
                placeholder = UIColor(white: 0.82, alpha: 1)
            } else {
                placeholder = UIColor(white: 0.45, alpha: 1)
            }
        } else {
            background = .white
            card = .white
            border = borderColor
            fieldText = .black
            placeholder = UIColor(white: 0.45, alpha: 1)
        }

        view.backgroundColor = background
        pushupTableView.backgroundColor = background
        pushupTableView.separatorColor = border

        let boxes = [dailyBox, weeklyBox, monthlyBox, yearlyBox]
        for box in boxes {
            box?.backgroundColor = card
            box?.layer.borderColor = border.cgColor
            if let box = box {
                for subview in box.subviews {
                    (subview as? UILabel)?.textColor = fieldText
                }
            }
        }

        numberLabel.textColor = fieldText

        let borderCG = border.cgColor
        upButton.layer.borderColor = borderCG
        downButton.layer.borderColor = borderCG
        saveButton.layer.borderColor = borderCG

        middleTextField.textColor = fieldText
        middleTextField.backgroundColor = card
        middleTextField.attributedPlaceholder = NSAttributedString(
            string: "Enter text here. Then save.",
            attributes: [NSAttributedStringKey.foregroundColor: placeholder]
        )
        saveButton.superview?.backgroundColor = background

        if let bar = keyboardDoneBar, let doneButton = keyboardDoneButton {
            bar.backgroundColor = card
            doneButton.backgroundColor = popColor
            doneButton.setTitleColor(fieldText, for: .normal)
            doneButton.layer.borderColor = borderCG
        }
        if let saveKeyboardButton = keyboardSaveButton {
            saveKeyboardButton.backgroundColor = popColor
            saveKeyboardButton.setTitleColor(fieldText, for: .normal)
            saveKeyboardButton.layer.borderColor = borderCG
        }
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
        let today = Date()

        var todaysPushupNumber = 0
        var thisWeeksPushups = 0
        var thisMonthsPushups = 0
        var thisYearsPushups = 0
        var pushupsAllTime = 0

        for workout in myArray {
            let date = workout.dateOfWorkout
            pushupsAllTime = pushupsAllTime + workout.numberOfPushups

            if calendar.isDateInToday(date) {
                todaysPushupNumber = todaysPushupNumber + workout.numberOfPushups
            }

            // Week and month numbers repeat every year, so they have to be
            // compared with the year too. Matching only ".weekOfYear" / ".month"
            // counted every September (and every week 37) from all prior years.
            if calendar.isDate(date, equalTo: today, toGranularity: .weekOfYear) {
                thisWeeksPushups = thisWeeksPushups + workout.numberOfPushups
            }
            if calendar.isDate(date, equalTo: today, toGranularity: .month) {
                thisMonthsPushups = thisMonthsPushups + workout.numberOfPushups
            }
            if calendar.isDate(date, equalTo: today, toGranularity: .year) {
                thisYearsPushups = thisYearsPushups + workout.numberOfPushups
            }
        }

        print(pushupsAllTime)

        pushupsTodayLabel.text = String(todaysPushupNumber)
        pushupsThisWeekLabel.text = String(thisWeeksPushups)
        pushupsThisMonthLabel.text = String(thisMonthsPushups)
        pushupsThisYearLabel.text = String(thisYearsPushups)
    }
    
    @IBAction func tappedSaveButton(_ sender: Any) {
        //add the saved Text to the array.
        let newDataObject = DataObject(argumentListOfStrings: [], argumentDateOfSave: Date(), argumentDateOfWorkout: Date(),  argumentNumberOfPushups: Int())
        
        if middleTextField.text != ""
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
        guard let dataURL = DataArchive.fileURL else {
            presentAlert(title: "Save Error",
                         message: "Pushup Hero could not find its storage folder, so this workout was not saved.")
            return
        }

        // If the existing history could not be read at launch, writing now would
        // replace a file we never understood with a single new workout. Preserve
        // the original bytes first — and if that fails, refuse to save at all.
        // Blocking one workout is recoverable; overwriting unread history is not.
        if loadFailed {
            guard DataMigrationManager.shared.quarantineUnreadableDataFile() else {
                presentAlert(title: "Cannot Save Yet",
                             message: "Pushup Hero could not read your existing workout file, and could not set a copy of it aside. Saving now would overwrite it, so this workout has not been saved. Freeing up storage space and reopening the app should resolve this.")
                return
            }
            loadFailed = false
        }

        // Build the candidate list without touching myArray. Only a write that
        // actually lands is allowed to change what the app thinks it has, so a
        // failed save followed by a retry cannot record the workout twice.
        var candidate = myArray
        candidate.insert(newDataObject, at: 0)

        do {
            try DataArchive.write(candidate, to: dataURL)
        } catch {
            print("ERROR: Failed to save data: \(error.localizedDescription)")
            presentAlert(title: "Save Error",
                         message: "Failed to save this workout, so it has not been recorded. Your previous history is untouched. Please try again.")
            return
        }

        myArray = candidate
        print("Data saved successfully. Total workouts: \(myArray.count)")

        pushupTableView.reloadData()
        pushupNumber = 0
        numberLabel.text = String(pushupNumber)
        calculatePushupCounts()

        middleTextField.text = ""
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
        guard let dataURL = DataArchive.fileURL else {
            print("ERROR: documents directory unavailable")
            myArray = []
            loadFailed = true
            pendingAlert = ("Data Load Error", "Pushup Hero could not open its storage folder. Your workout history could not be loaded.")
            return
        }

        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            print("No existing data file found. Starting fresh.")
            myArray = []
            return
        }

        do {
            myArray = try DataArchive.read(from: dataURL)
            loadFailed = false
            print("Successfully loaded \(myArray.count) workouts")
        } catch {
            // Do not treat this as an empty history. myArray is left empty so the
            // UI has something to show, but loadFailed blocks the next save from
            // overwriting a file we could not read. That flag is the difference
            // between "you have no workouts yet" and "your workouts are gone".
            print("ERROR: Failed to load data: \(error.localizedDescription)")
            myArray = []
            loadFailed = true
            pendingAlert = ("Data Load Error",
                            "Your workout history could not be read. Nothing has been deleted \u{2014} the original file has been kept, and Pushup Hero will set it aside rather than overwrite it when you save your next workout.")
        }
    }

    /// Alerts raised during viewDidLoad cannot be presented yet, because the view
    /// is not in the window hierarchy. They are queued here and shown once it is.
    func presentPendingAlertIfNeeded() {
        guard let pending = pendingAlert else { return }
        pendingAlert = nil
        presentAlert(title: pending.title, message: pending.message)
    }

    @objc func showStats() {
        let statsViewController = StatsViewController(workouts: myArray, loadFailed: loadFailed)
        statsViewController.modalPresentationStyle = .fullScreen
        present(statsViewController, animated: true, completion: nil)
    }

    func presentAlert(title: String, message: String) {
        guard presentedViewController == nil else {
            // Something else is already on screen; try again once it is gone.
            pendingAlert = (title, message)
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc func handleSetLongPress(_ press: UILongPressGestureRecognizer) {
        guard press.state == .began else { return }
        guard presentedViewController == nil else { return }

        let point = press.location(in: pushupTableView)
        guard let indexPath = pushupTableView.indexPathForRow(at: point),
              indexPath.row < myArray.count else {
            return
        }

        pushupTableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        confirmDeleteSet(at: indexPath)
    }

    func confirmDeleteSet(at indexPath: IndexPath) {
        let workout = myArray[indexPath.row]
        let alert = UIAlertController(title: "Are you sure you want to delete this set?",
                                      message: "It can't be recovered",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            self.pushupTableView.deselectRow(at: indexPath, animated: true)
        }))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            self.deleteSet(workout)
        }))
        present(alert, animated: true)
    }

    func deleteSet(_ workout: DataObject) {
        guard let index = myArray.firstIndex(where: { $0 === workout }) else { return }

        guard let dataURL = DataArchive.fileURL else {
            presentAlert(title: "Delete Error",
                         message: "Pushup Hero could not find its storage folder, so this set was not deleted.")
            return
        }

        // Same rule as save: if the existing history could not be read, writing
        // now would replace a file we never understood. Preserve it first.
        if loadFailed {
            guard DataMigrationManager.shared.quarantineUnreadableDataFile() else {
                presentAlert(title: "Cannot Delete Yet",
                             message: "Pushup Hero could not read your existing workout file, and could not set a copy of it aside. Deleting now would overwrite it, so this set has not been removed. Freeing up storage space and reopening the app should resolve this.")
                return
            }
            loadFailed = false
        }

        var candidate = myArray
        candidate.remove(at: index)

        do {
            try DataArchive.write(candidate, to: dataURL)
        } catch {
            print("ERROR: Failed to delete set: \(error.localizedDescription)")
            presentAlert(title: "Delete Error",
                         message: "Failed to delete this set, so it is still in your history. Please try again.")
            pushupTableView.deselectRow(at: IndexPath(row: index, section: 0), animated: true)
            return
        }

        myArray = candidate
        DataMigrationManager.shared.recordIntentionalDeletion(remainingCount: myArray.count)

        pushupTableView.reloadData()
        calculatePushupCounts()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let workout = myArray[indexPath.row]
        let cell: pushupCell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! pushupCell
        
        cell.pushupLabel.text = String(workout.numberOfPushups)
        
        formatter.dateFormat = "MMM d yyyy, h:mm a"
        let formattedDate = formatter.string(from: (workout.dateOfWorkout))
        cell.dateLabel.text = formattedDate

        cell.nameLabel.text = workout.listOfStrings.last

        if #available(iOS 13.0, *) {
            cell.backgroundColor = .systemBackground
            cell.contentView.backgroundColor = .systemBackground
            cell.pushupLabel.textColor = .label
            cell.nameLabel.textColor = .label
            cell.dateLabel.textColor = .secondaryLabel
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return myArray.count
    }
    
//    func textFieldDidBeginEditing(_ middleTextField: UITextField) {
//        middleTextField.text = ""
//    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

/// Fixed-height bar so the Done button sits fully above the keyboard instead of
/// overlapping it. UIToolbar on current iOS draws a floating pill with no bar.
final class KeyboardDoneAccessory: UIView {
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIViewNoIntrinsicMetric, height: 48)
    }
}
