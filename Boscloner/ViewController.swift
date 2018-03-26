//
//  ViewController.swift
//  Boscloner
//
//  Created by Phillip Bosco on 3/17/18.
//  Copyright © 2018 Phillip Bosco. All rights reserved.
//

import UIKit
import CoreBluetooth
import UserNotifications

extension UITableView {
    
    func tableViewScrollToBottom(animated: Bool) {
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            
            let numberOfSections = self.numberOfSections
            let numberOfRows = self.numberOfRows(inSection: numberOfSections-1)
            if numberOfRows > 0 {
                let indexPath = IndexPath(row: numberOfRows-1, section: (numberOfSections-1))
                self.scrollToRow(at: indexPath, at: UITableViewScrollPosition.bottom, animated: animated)
            }
        }
    }
}

//Global Variable - History Log File
var historyLogFile = [String]()
var historyLogFileShort = [String]()

// Global Variables - BLE Info for HistoryViewController's Write Operations from Log File
var connectedPeripheral: CBPeripheral!
var writeCharacteristic: CBCharacteristic!


class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate, UITableViewDelegate, UITableViewDataSource, UITabBarDelegate {
    
    // BLE Device Info
    let BLUE_HOME_SERVICE = "FFE0"
    let WRITE_CHARACTERISTIC = "FFE1"
    let READ_CHARACTERISTIC = "FFE1"
    
    var centralManager: CBCentralManager!
    
    var readCharacteristic: CBCharacteristic!
    
    // Terminal Output (In original file)
    var characteristicASCIIValue = NSString()
    
    //Clone Commands
    let cmdCloneGenericTest : String = "$!CLONE,0102030405?$"
    let cmdAutoCloneDisabled : String = "$!DISABLE_CLONE?$"
    let cmdAutoCloneEnabled : String = "$!ENABLE_CLONE?$"
    
    var currentTimeStamp = ""
    
    var firstRun : Bool = true
    
    // Using Arrays to Merge Fragmented BT Packets into Complete Strings
    var parsingArray = [String]()
    var receivedArray = [String]()
    var newString : String = ""
    
    // Testing out a table view
    let terminalPrefix : String = "Boscloner$"
    var terminalOutput = [String]()
    
    
    // For app notifications
    let center = UNUserNotificationCenter.current()
    let options : UNAuthorizationOptions = [.alert, .sound, .badge];
    
    
    // User Defaults - Called in ViewDidLoad
    let defaults = UserDefaults.standard
    var RFIDBadgeType : String = "typeHIDProx"
    var autoCloneDefault : String = "1"    // 1 == AutoClone Enabled, 2 == AutoClone Disabled
    
    var customWriteGlitch : Bool = true  // Since MCU Status is sent on both autoclone toggle and custom write, the app's state can get confused. This Bool keeps things on track.
    
    
    // IBOutlets and IBActions
    @IBAction func customWriteIcon(_ sender: UIButton) {
        showInputDialog()
    }
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var shadowView: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var uiSwitch: UISwitch!
    
    // AutoClone Button - Manual Toggle
    @IBAction func uiSwitchValueChanged(_ sender: UISwitch) {
        
        if (sender.isOn) {
            print("AutoClone is ON")
            customWriteGlitch = true
            writeBLEData(string: cmdAutoCloneEnabled)
            autoCloneDefault = "1"
            self.tableView.tableViewScrollToBottom(animated: true)
            
        }
        else {
            print("AutoClone is OFF")
            customWriteGlitch = true
            writeBLEData(string: cmdAutoCloneDisabled)
            autoCloneDefault = "0"
            self.tableView.tableViewScrollToBottom(animated: true)
        }
        
    }
    
    
    // Triggers when app is first loaded
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // User Defaults
        
        defaults.register(defaults: [String : Any]())
        if let defaultRFIDBadgeType = defaults.string(forKey: "default_rfid_type") {
            RFIDBadgeType = defaultRFIDBadgeType
            print("Default RFID Badge Type loaded from user preferences: \(RFIDBadgeType)")
        } else {
            print("Unknown Default Badge Type, Resorting to: \(RFIDBadgeType)")
        }
        
        
        if let defaultAutoCloneSetting = defaults.string(forKey: "default_autoclone_setting") {
            autoCloneDefault = defaultAutoCloneSetting
            print("AutoClone Default Loaded from User Preferences and is Set to: \(autoCloneDefault)")
        } else {
            print("Unknown AutoClone Default, Resorting to: \(autoCloneDefault)")
        }
        
        
        // Change Main AutoClone Switch Visual to Reflect User Defaults
        if autoCloneDefault == "1" {
            print("Changing Visual screw up. Set to 1")
            uiSwitch.isOn = true
        } else if autoCloneDefault == "0" {
            print("change visual screw up. set to 0")
            uiSwitch.isOn = false
        }
        
        
        if let defaultHistoryLogFile = UserDefaults.standard.array(forKey: "HistoryLogFileKey") as? [String] {
            historyLogFile = defaultHistoryLogFile
            print("Loaded from user defaults! Here is what was stored: \(historyLogFile)")
        } else {
            print("No default history file to load. Using empty file that was set globally.")
        }
        
        if let defaultHistoryLogFileShort = UserDefaults.standard.array(forKey: "HistoryLogFileShortKey") as? [String] {
            historyLogFileShort = defaultHistoryLogFileShort
            print("Loaded from user defaults! Here is what was stored in: \(historyLogFileShort)")
        } else {
            print("No default history file to load. Using empty file that was set globally.")
        }
        
        
        
        // Setting Delegates and Such
        centralManager = CBCentralManager(delegate: self, queue: nil)
        tableView.dataSource = self
        tableView.delegate = self
        
        //notification test
        center.requestAuthorization(options: options) {
            (granted, error) in
            if !granted {
                print("Something went wrong")
            }
        }
        
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Attempt to make a BLE Connection
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(ViewController.scanForBLEDevice), userInfo: nil, repeats: false)
        
        activityIndicator.startAnimating()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Close BLE Connection if it exists
    }
    
    //Begin BLE Scanning for devices that use FFE0
    @objc func scanForBLEDevice() {
        centralManager.scanForPeripherals(withServices: [CBUUID(string:BLUE_HOME_SERVICE)], options: nil)
        
    }
    
    
    // Discovering BLE Devices
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if (peripheral.name != nil) {
            print("Found Peripheral: \(peripheral.name!)")
        }
        else {
            print("Found something with unknown name")
        }
        
        // Save reference to the peripheral
        
        connectedPeripheral = peripheral
        
        centralManager.stopScan()
        print("Stopping Scan")
        
        centralManager.connect(connectedPeripheral, options: nil)
        print("Connecting to Peripheral...")
        
    }
    
    
    // Once peripheral is connected, the following callback runs
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        print("Connected to the device!")
        
        hideActivityIndicator()
        
        connectedPeripheral.delegate = self
        
        connectedPeripheral.discoverServices(nil)
    }
    
    
    // Discover Services on Connected Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("Service Count =\(peripheral.services!.count)")
        
        for service in peripheral.services! {
            print("Service= \(service)")
            
            let aService = service as CBService
            
            if service.uuid == CBUUID(string: BLUE_HOME_SERVICE) {
                // Discover characteristics for our service
                
                peripheral.discoverCharacteristics(nil, for: aService)
            }
        }
        
    }
    
    // Discover Characteristics of Services and Enabled Notifications (Allowing the App to Receive Data from BLE)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        for characteristic in service.characteristics! {
            let aCharacteristic = characteristic as CBCharacteristic
            
            if aCharacteristic.uuid == CBUUID(string: WRITE_CHARACTERISTIC) {
                writeCharacteristic = aCharacteristic
                readCharacteristic = aCharacteristic
                print("Identified write characteristics: \(writeCharacteristic)")
                connectedPeripheral.setNotifyValue(true, for: readCharacteristic)
                
            }
        }
    }
    
    
    //Notification Status Change
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        
        if ((error) != nil) {
            NSLog("Error changing notification state: %@", error?.localizedDescription ?? "empty");
        }
        
        // Notification has started
        if (characteristic.isNotifying) {
            NSLog("Ready to Receive Data", characteristic);
        }
        
        // Changing the board to reflect user's default autoclone setting
        // Putting this here, because it can only be changed after a successful BLE connection
        userDefaultAutoCloneFunction()
    }
    
    
    // Receiving the notification
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        
        if let ASCIIstring = NSString(data: characteristic.value!, encoding: String.Encoding.utf8.rawValue) {
            characteristicASCIIValue = ASCIIstring
            print("Value Received: \((characteristicASCIIValue as String))")
            NotificationCenter.default.post(name:NSNotification.Name(rawValue: "Notify"), object: nil)
            
            // Doing Formatting Stuff
            newString = (characteristicASCIIValue as String)
            parsingArray.append(newString)
            newString = parsingArray.reduce("",{$0 + $1})
            
            //          String Contains SCAN - Isolated the Badge ID
            if newString.contains("SCAN") && newString.contains("?$") {
                print(newString + " Offsetting SCAN String")
                
                let start = newString.index(newString.startIndex, offsetBy: 7)
                let end = newString.index(newString.endIndex, offsetBy: -3)
                let range = start..<end
                print("Boscloner$ " + newString[range])
                newString = String(newString[range])
                autoCloneDefault = "0"
                updateUI(badgeID: newString)
            }
                
            else if newString.contains("CLONE") && newString.contains("?$") {
                print(newString + " Offsetting CLONE STRING")
                
                let start = newString.index(newString.startIndex, offsetBy: 8)
                let end = newString.index(newString.endIndex, offsetBy: -3)
                let range = start..<end
                print("Boscloner$ " + newString[range])
                newString = String(newString[range])
                autoCloneDefault = "1"
                updateUI(badgeID: newString)
            }
                
            else if newString.contains("STATUS,MCU") && customWriteGlitch == true {
                newString = ""
                parsingArray = [String]()
                
                if autoCloneDefault == "1" && firstRun == true{
                    terminalOutput.append("**AutoClone Status: Enabled**")
                    terminalOutput.append("**RFID Badge Type: \(RFIDBadgeType)**")
                    terminalOutput.append("---------------")
                    terminalOutput.append("Boscloner$    (Ready to Receive Data)")
                    firstRun = false
                }
                    
                else if autoCloneDefault == "0" && firstRun == true {
                    terminalOutput.append("**AutoClone Status: Disabled**")
                    terminalOutput.append("**RFID Badge Type: \(RFIDBadgeType)**")
                    terminalOutput.append("---------------")
                    terminalOutput.append("Boscloner$    (Ready to Receive Data)")
                    firstRun = false
                }
                    
                else if autoCloneDefault == "1" && firstRun == false {
                    terminalOutput.append("**AutoClone Status: Enabled**")
                }
                    
                    
                else if autoCloneDefault == "0" && firstRun == false {
                    terminalOutput.append("**AutoClone Status: Disabled**")
                }
                
                tableView.reloadData()
                print("AutoClone Toggled. Clearing Strings. Waiting for more data.")
            }
                
            else if newString.contains("STATUS,MCU") && customWriteGlitch == false {
                newString = ""
                parsingArray = [String]()
                tableView.reloadData()
                print("Custom Data Written. Ignoring STATUS,MCU Signal")
                
            }
        }
            
        else {
            print("Data set not complete. Nothing to print just yet")
        }
        
    }
    
    
    // Update UI and History Log File with Newly Retrieved Badge ID
    func updateUI(badgeID : String) {
        timestampRoutine()
        historyLogFile.append(badgeID + "               " + currentTimeStamp)
        historyLogFileShort.append(badgeID)
        self.defaults.set(historyLogFile, forKey: "\(badgeID)" + "               " + "\(currentTimeStamp)")
        self.defaults.set(historyLogFileShort, forKey: "\(badgeID)")
        parsingArray = [String]()
        newString = ""
        terminalOutput.append("Boscloner$    \(badgeID)")
        
        notificationBadgeCaptured(notificationBadgeID: badgeID)
        
        //        print("\(historyLogFile) + \n New Contents of History log file")
        print("\(historyLogFileShort) + \n New Contents of History log file - short")
        
        tableView.reloadData()
        
        self.tableView.tableViewScrollToBottom(animated: true)
        
        self.defaults.set(historyLogFile, forKey: "HistoryLogFileKey")
        self.defaults.set(historyLogFileShort, forKey: "HistoryLogFileShortKey")
    }
    
    
    // Send Data to Boscloner Board
    func writeBLEData(string: String) {
        
        let data = string.data(using: String.Encoding.ascii)
        
        print("Writing the data: \(data!)")
        
        connectedPeripheral.writeValue(data!, for: writeCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
    }
    
    @objc func hideActivityIndicator() {
        activityIndicator.stopAnimating()
        shadowView.isHidden = true
    }
    
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    //Central Manager Delegates
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("centralManagerDidUpdateState: started")
        
        switch(central.state){
        case .poweredOff:
            print("Power is Off")
        case .unknown:
            print("case unknown")
        case .resetting:
            print("case resetting")
        case .unsupported:
            print("case unsupported")
        case .unauthorized:
            print("case unauthorized")
        case .poweredOn:
            print("Power is On")
        }
    }
    
    
    // Adding Necessary Protocol Stubs for TableView
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection: Int) -> Int {
        return terminalOutput.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cellReuseIdentifier")!
        let text = terminalOutput[indexPath.row]
        
        cell.textLabel?.text = text
        cell.textLabel?.textColor = UIColor.green
        return cell
    }
    
    
    // Adding the Pop-Up Dialog for Custom Writing of Badges
    func showInputDialog() {
        let alertController = UIAlertController(title: "Write Custom Badge", message: "Enter Custom Badge ID \n (Format: 1A:2B:3C:4D:5E)", preferredStyle: .alert)
        
        //the confirm action taking the inputs
        let confirmAction = UIAlertAction(title: "Enter", style: .default) { (_) in
            
            //getting the input values from user
            if let customBadgeString = alertController.textFields?[0].text {
                self.writeCustomBadge(customBadge: "\(customBadgeString)")
            }
            
        }
        
        //the cancel action doing nothing
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in }
        
        //adding textfields to our dialog box
        alertController.addTextField { (textField) in
            textField.placeholder = "1A:2B:3C:4D:5E"
        }
        
        //adding the action to dialogbox
        alertController.addAction(confirmAction)
        alertController.addAction(cancelAction)
        
        //finally presenting the dialog box
        self.present(alertController, animated: true, completion: nil)
    }
    
    func writeCustomBadge(customBadge: String) {
        customWriteGlitch = false
        writeBLEData(string: "$!CLONE,\(customBadge)?$")
        terminalOutput.append("Custom ID Written: \(customBadge)")
        timestampRoutine()
        historyLogFile.append(customBadge + "               " + currentTimeStamp)
        historyLogFileShort.append(customBadge)
        self.defaults.set(historyLogFile, forKey: "\(customBadge)" + "               " + "\(currentTimeStamp)")
        self.defaults.set(historyLogFileShort, forKey: "\(customBadge)")
        tableView.reloadData()
        self.tableView.tableViewScrollToBottom(animated: true)
    }
    
    func writeCustomBadgeFromHistory(historyBadge: String) {
        customWriteGlitch = false
        writeBLEData(string: "$!CLONE,\(historyBadge)?$")
        terminalOutput.append("On-Demand Write from History: \(historyBadge)")
    }
    
    
    // Creating Timestamp for History File
    func timestampRoutine() {
        let date = Date() // save date, so all components use the same date
        let calendar = Calendar.current
        
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        
        currentTimeStamp = "\(month)-\(day)-\(year)  \(hour):\(minute):\(second)"
        //        currentTimeStamp = String(describing: Date())
        
    }
    // Sending Local Notification When Badge is Captured
    func notificationBadgeCaptured(notificationBadgeID: String) {
        let content = UNMutableNotificationContent()
        content.title = "Badge Captured"
        content.body = notificationBadgeID
        content.sound = UNNotificationSound.default()
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: "notification.id.01", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        //        print("badge Captured! Notification Sent")
        
    }
    
    
    
    //     User Default Functions - Called in "didUpdateNotificationStateFor"
    
    func userDefaultAutoCloneFunction() {
        if autoCloneDefault == "1" {
            //            uiSwitch.isOn = true
            writeBLEData(string: cmdAutoCloneEnabled)
            
        }
        else if autoCloneDefault == "0" {
            //            uiSwitch.isOn = false
            customWriteGlitch = true
            writeBLEData(string: cmdAutoCloneDisabled)
        }
    }
    
    
    
}

