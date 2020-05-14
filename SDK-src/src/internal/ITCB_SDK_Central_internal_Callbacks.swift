/*
© Copyright 2020, Little Green Viper Software Development LLC

LICENSE:

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Little Green Viper Software Development LLC: https://littlegreenviper.com
*/

import CoreBluetooth

/* ###################################################################################################################################### */
// MARK: - CBCentralManagerDelegate Conformance -
/* ###################################################################################################################################### */
extension ITCB_SDK_Central: CBCentralManagerDelegate {
    /* ################################################################## */
    /**
     This is called as the state changes for the Central manager object.
     
     - parameter inCentralManager: The Central Manager instance that changed state.
     */
    public func centralManagerDidUpdateState(_ inCentralManager: CBCentralManager) {
        assert(inCentralManager === managerInstance)   // Make sure that we are who we say we are...
        // Once we are powered on, we can start scanning.
        if .poweredOn == inCentralManager.state {
            inCentralManager.scanForPeripherals(withServices: [_static_ITCB_SDK_8BallServiceUUID], options: [:])
        }
    }

    /* ################################################################## */
    /**
     This is called as the state changes for the Central manager object.
     
     - parameters:
        - inCentralManager: The Central Manager instance that changed state.
        - didDiscover: This is the Core Bluetooth Peripheral instance that was discovered.
        - advertisementData: This is the adverstiement data that was sent by the discovered Peripheral.
        - rssi: This is the signal strength of the discovered Peripheral.
     */
    public func centralManager(_ inCentralManager: CBCentralManager, didDiscover inPeripheral: CBPeripheral, advertisementData inAdvertisementData: [String : Any], rssi inRSSI: NSNumber) {
        assert(inCentralManager === managerInstance)    // Make sure that we are who we say we are...
        if  !devices.contains(inPeripheral),            // Make sure that we don't already have this peripheral.
            let peripheralName = inPeripheral.name,     // And that it is a legit Peripheral (has a name).
            !peripheralName.isEmpty,
            (_static_ITCB_SDK_RSSI_Min..._static_ITCB_SDK_RSSI_Max).contains(inRSSI.intValue) { // and that we have a signal within the acceptable range.
            devices.append(ITCB_SDK_Device_Peripheral(inPeripheral, owner: self))   // By creating this, we develop a strong reference, which will keep the CBPeripheral around.
            inCentralManager.connect(inPeripheral, options: nil)    // We initiate a connection, which starts the voyage of discovery.
        }
    }
    
    /* ################################################################## */
    /**
     This is called when a peripheral was connected.
     
     Once the device is connected, we can start discovering services.
     
     - parameters:
        - inCentralManager: The Central Manager instance that changed state.
        - didConnect: This is the Core Bluetooth Peripheral instance that was discovered.
     */
    public func centralManager(_ inCentralManager: CBCentralManager, didConnect inPeripheral: CBPeripheral) {
        inPeripheral.discoverServices([_static_ITCB_SDK_8BallServiceUUID])
    }
}

/* ###################################################################################################################################### */
// MARK: - CBPeripheralDelegate Conformance -
/* ###################################################################################################################################### */
extension ITCB_SDK_Device_Peripheral: CBPeripheralDelegate {
    /* ################################################################## */
    /**
     Called after the Peripheral has discovered Services.
     
     - parameter inPeripheral: The Peripheral object that discovered (and now contains) the Services.
     - parameter didDiscoverServices: Any errors that may have occurred. It may be nil.
     */
    public func peripheral(_ inPeripheral: CBPeripheral, didDiscoverServices inError: Error?) {
        // After discovering the Service, we ask it (even though we are using an Array visitor) to discover its three Characteristics.
        inPeripheral.services?.forEach {
            // Having all 3 Characteristic UUIDs in this call, means that we should get one callback, with all 3 Characteristics set at once.
            inPeripheral.discoverCharacteristics([_static_ITCB_SDK_8BallService_Question_UUID,
                                                  _static_ITCB_SDK_8BallService_Answer_UUID], for: $0)
        }
    }
    
    /* ################################################################## */
    /**
     Called after the Peripheral has discovered Services.
     
     - parameter inPeripheral: The Peripheral object that discovered (and now contains) the Services.
     - parameter didDiscoverCharacteristicsFor: The Service that had the Characteristics discovered.
     - parameter error: Any errors that may have occurred. It may be nil.
     */
    public func peripheral(_ inPeripheral: CBPeripheral, didDiscoverCharacteristicsFor inService: CBService, error inError: Error?) {
        if _characteristicInstances.isEmpty {   // Make sure that we didn't already pick up the Characteristics (This can be called multiple times).
            _characteristicInstances = inService.characteristics ?? []
            owner.peripheralServicesUpdated(self)
        }
    }
    
    /* ################################################################## */
    /**
     Called when the Peripheral updates a Characteristic (the Answer).
     The inCharacteristic.value field can be considered valid.
     
     - parameter inPeripheral: The Peripheral object that discovered (and now contains) the Services.
     - parameter didUpdateValueFor: The Characteristic that was updated.
     - parameter error: Any errors that may have occurred. It may be nil.
     */
    public func peripheral(_ inPeripheral: CBPeripheral, didUpdateValueFor inCharacteristic: CBCharacteristic, error inError: Error?) {
        if  let answerData = inCharacteristic.value,
            let answerString = String(data: answerData, encoding: .utf8),
            !answerString.isEmpty {
            _timeoutTimer?.invalidate()  // Stop our timeout timer.
            _timeoutTimer = nil
            inPeripheral.setNotifyValue(false, for: inCharacteristic)
            answer = answerString
        }
    }

    /* ################################################################## */
    /**
     Called when the Peripheral updates a Characteristic that we wanted written (the Question).
     NOTE: The inCharacteristic.value field IS NOT VALID in this call. That's why we saved the _interimQuestion property.
     
     - parameter inPeripheral: The Peripheral object that discovered (and now contains) the Services.
     - parameter didWriteValueFor: The Characteristic that was updated.
     - parameter error: Any errors that may have occurred. It may be nil.
     */
    public func peripheral(_ inPeripheral: CBPeripheral, didWriteValueFor inCharacteristic: CBCharacteristic, error inError: Error?) {
        if  nil == inError {
            if let questionString = _interimQuestion {  // We should have had an interim question queued up.
                question = questionString
            } else {
                owner._sendErrorMessageToAllObservers(error: .sendFailed(ITCB_RejectionReason.peripheralError(nil)))
            }
        } else {
            _timeoutTimer?.invalidate()  // Stop our timeout timer. We only need the one error.
            _timeoutTimer = nil
            if let error = inError as? CBATTError {
                switch error {
                // We get an "unlikely" error only when there was no question mark, so we are safe in assuming that.
                case CBATTError.unlikelyError:
                    owner._sendErrorMessageToAllObservers(error: .sendFailed(ITCB_Errors.coreBluetooth(ITCB_RejectionReason.questionPlease)))

                // For everything else, we simply send the error back, wrapped in the "sendFailed" error.
                default:
                    owner._sendErrorMessageToAllObservers(error: .sendFailed(ITCB_Errors.coreBluetooth(ITCB_RejectionReason.peripheralError(error))))
                }
            } else {
                owner._sendErrorMessageToAllObservers(error: .sendFailed(ITCB_RejectionReason.unknown(inError)))
            }
        }
    }
    
    /* ################################################################## */
    /**
     Called when the Peripheral makes a change to a Service. In the case of this app, that generally means that the Peripheral was disconnected.
     We can assume that, if we get this call, the Peripheral has been disconnected.
     
     - parameter inPeripheral: The Peripheral object that experienced the changed Services.
     - parameter didModifyServices: The Services (as an Array) that were changed.
     */
    public func peripheral(_ inPeripheral: CBPeripheral, didModifyServices inInvalidatedServices: [CBService]) {
        // For now, we will simply return an error, but we'll revisit this later.
        owner._sendErrorMessageToAllObservers(error: .sendFailed(ITCB_Errors.coreBluetooth(ITCB_RejectionReason.deviceOffline)))
    }
}
