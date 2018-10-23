//
//  Async.swift
//  Async
//
//  Created by Mahyar Zhiani on 5/9/1397 AP.
//  Copyright © 1397 Mahyar Zhiani. All rights reserved.
//

import Foundation
import Starscream
import SwiftyJSON


public class Async {
    
    public weak var delegate: AsyncDelegates?
    
    private var socketAddress:          String      // socket address
    private var serverName:             String      // server to register on
    private var deviceId:               String      // the user current device id
    
    private var appId:                  String      //
    private var peerId:                 Int         //
    private var messageTtl:             Int         //
    private var connectionRetryInterval:Int         //
    private var reconnectOnClose:       Bool        // should
    
    // Async initializer
    public init(socketAddress: String,
                serverName: String,
                deviceId: String,
                appId: String?,
                peerId: Int?,
                messageTtl: Int?,
                connectionRetryInterval: Int?,
                reconnectOnClose: Bool?) {
        
        self.socketAddress = socketAddress
        self.serverName = serverName
        self.deviceId = deviceId
        
        if let theAppId = appId {
            self.appId = theAppId
        } else {
            self.appId = "POD-Chat"
        }
        if let thePeerId = peerId {
            self.peerId = thePeerId
        } else {
            self.peerId = 0
        }
        if let theMessageTtl = messageTtl {
            self.messageTtl = theMessageTtl
        } else {
            self.messageTtl = 5
        }
        if let theConnectionRetryInterval = connectionRetryInterval {
            self.connectionRetryInterval = theConnectionRetryInterval
        } else {
            self.connectionRetryInterval = 5
        }
        if let theReconnectOnClose = reconnectOnClose {
            self.reconnectOnClose = theReconnectOnClose
        } else {
            self.reconnectOnClose = true
        }
    }
    
    
    private var oldPeerId: Int?
    private var isSocketOpen        = false
    private var isDeviceRegister    = false
    private var isServerRegister    = false
    
    private var socketState         = socketStateType.CONNECTING
    private var asyncState          = ""
    
//    private var registerServerTimeoutId: Int        = 0
//    private var registerDeviceTimeoutId: Int        = 0
    private var checkIfSocketHasOpennedTimeoutId:   Int = 0
    private var socketReconnectRetryInterval:       Int = 0
    private var socketReconnectCheck:               Int = 0
    
    private var lastMessageId           = 0
    private var retryStep:      Double  = 1
//    var asyncReadyTimeoutId
    private var pushSendDataArr         = [[String: Any]]()
    
//    var waitForSocketToConnectTimeoutId: Int
    var wsConnectionWaitTime:           Int = 5
    var connectionCheckTimeout:         Int = 10
    var lastReceivedMessageTime:        Date?
    var lastReceivedMessageTimeoutId:   RepeatingTimer?
    
    var lastSentMessageTime:            Date?
    var lastSentMessageTimeoutIdTimer:  RepeatingTimer?
    var socketRealTimeStatusInterval:   RepeatingTimer?
    
    var socket: WebSocket?
    
    public func createSucket() {
        var request = URLRequest(url: URL(string: socketAddress)!)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
        startTimers()
        socket?.connect()
    }
    
    var t = RepeatingTimer(timeInterval: 0)
    
    var checkIfSocketHasOpennedTimeoutIdTimer:  RepeatingTimer?
    var socketReconnectRetryIntervalTimer:      RepeatingTimer?
    var socketReconnectCheckTimer:              RepeatingTimer?
    
    func startTimers() {
        checkIfSocketHasOpennedTimeoutIdTimer = RepeatingTimer(timeInterval: 65)
        checkIfSocketHasOpennedTimeoutIdTimer?.eventHandler = {
            self.checkIfSocketIsCloseOrNot()
            self.checkIfSocketHasOpennedTimeoutIdTimer?.suspend()
        }
        checkIfSocketHasOpennedTimeoutIdTimer?.resume()
    }
    
    
    var registerServerTimeoutIdTimer: RepeatingTimer?
    
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\


// methods on socket connection
extension Async {
    
    // MARK: - when socket is connected, this func will trigger
    func handleOnOppendSocket() {
        DispatchQueue.global().async {
            self.checkIfSocketHasOpennedTimeoutIdTimer?.suspend()
            self.socketReconnectRetryIntervalTimer?.suspend()
            self.socketReconnectCheckTimer?.suspend()
        }
        isSocketOpen = true
        delegate?.asyncConnect(newPeerID: peerId)
        retryStep = 1
        socketState = socketStateType.OPEN
        delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
    }
    
    
    // MARK: - when socket is closed, this func will trigger
    func handleOnClosedSocket() {
        print("\n ON Async")
        print(".. \t handleOnClossedSocket \t")
        isSocketOpen = false
        isDeviceRegister = false
        oldPeerId = peerId
        
        socketState = socketStateType.CLOSED
        
        delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
        delegate?.asyncDisconnect()
        
        if (reconnectOnClose) {
            socketState = socketStateType.CLOSED
            delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: Int(retryStep), deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
            
            t = RepeatingTimer(timeInterval: retryStep)
            t.eventHandler = {
                if (self.retryStep < 60) {
                    self.retryStep = self.retryStep * 2
                }
                DispatchQueue.main.async {
                    print("\n ON Async")
                    print(".. \t try to connect to the socket on the main threat\n")
                    self.socket?.connect()
                    self.t.suspend()
                }
            }
            t.resume()
            
            
        } else {
            delegate?.asyncError(errorCode: 4005, errorMessage: "Socket Closed!", errorEvent: nil)
            delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
        }
        
    }
    
    // MARK: - when message recieves from socket, this func will trigger
    func handleOnRecieveMessage(messageRecieved: String) {
        
        lastReceivedMessageTime = Date()
        
        if let dataFromMsgString = messageRecieved.data(using: .utf8, allowLossyConversion: false) {
            do {
                let msg = try JSON(data: dataFromMsgString)
                //                print("\(msg)")
                //                let msgId = msg["id"].intValue
                //                let msgSenderMessageId = msg["senderMessageId"].intValue
                //                let msgSenderName = msg["senderName"].stringValue
                //                let msgSenderId = msg["senderId"].intValue
                //                let msgType = msg["type"].intValue
                //                let msgCont = msg["content"].stringValue
                //                var msgTrackerId: Int = 0
                //                if let tId = msg["trackerId"].int {
                //                    msgTrackerId = tId
                //                }
                //
                //                let msgContent: JSON = ["id": msgId,"senderMessageId": msgSenderMessageId,"senderName": msgSenderName,"senderId": msgSenderId,"type": msgType,"content": msgCont,"trackerId": msgTrackerId]
                
                switch msg["type"].intValue {
                case asyncMessageType.PING.rawValue:
                    handlePingMessage(message: msg)
                case asyncMessageType.SERVER_REGISTER.rawValue:
                    handleServerRegisterMessage(message: msg)
                case asyncMessageType.DEVICE_REGISTER.rawValue:
                    handleDeviceRegisterMessage(message: msg)
                case asyncMessageType.MESSAGE.rawValue:
                    delegate?.asyncReceiveMessage(params: msg)
                case asyncMessageType.MESSAGE_ACK_NEEDED.rawValue, asyncMessageType.MESSAGE_SENDER_ACK_NEEDED.rawValue:
                    handleSendACK(messageContent: msg)
                    delegate?.asyncReceiveMessage(params: msg)
                case asyncMessageType.ACK.rawValue:
                    delegate?.asyncReceiveMessage(params: msg)
                case asyncMessageType.ERROR_MESSAGE.rawValue:
                    delegate?.asyncError(errorCode: 4002, errorMessage: "Async Error!", errorEvent: msg)
                default:
                    return
                }
            } catch {
                //                print("MyLog: error to convert income message String to JSON")
            }
        } else { print(".. \t error to get message from server") }
        
        // set timer to check if need to close the socket!
        handleIfNeedsToCloseTheSocket()
    }
    
    
    func handleIfNeedsToCloseTheSocket() {
        self.lastReceivedMessageTimeoutId?.suspend()
        DispatchQueue.global().async {
            self.lastReceivedMessageTimeoutId = RepeatingTimer(timeInterval: (TimeInterval(self.connectionCheckTimeout) * 1.5))
            self.lastReceivedMessageTimeoutId?.eventHandler = {
                if let lastReceivedMessageTimeBanged = self.lastReceivedMessageTime {
                    let elapsed = Date().timeIntervalSince(lastReceivedMessageTimeBanged)
                    let elapsedInt = Int(elapsed)
                    if (elapsedInt >= self.connectionCheckTimeout) {
                        DispatchQueue.main.async {
                            self.socket?.disconnect()
                        }
                        self.lastReceivedMessageTimeoutId?.suspend()
                    }
                }
            }
            self.lastReceivedMessageTimeoutId?.resume()
        }
    }
    
    
    func handlePingMessage(message: JSON) {
        if (!isDeviceRegister) {
            if (message["id"].int != nil) {
                registerDevice()
            } else {
                delegate?.asyncError(errorCode: 4003, errorMessage: "Device Id is not present!", errorEvent: nil)
            }
        }
        
    }
    
    
    func handleDeviceRegisterMessage(message: JSON) {
        guard message != [] else { return }
        if (!isDeviceRegister) {
            isDeviceRegister = true
            peerId = message["content"].intValue
        }
        
        peerId = message["content"].intValue
        socketState = socketStateType.OPEN
        
        delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
        if (isServerRegister == true && peerId == oldPeerId) {
            sendDataFromQueueToSocekt()
            delegate?.asyncReady()
        } else {
            print("\n ON Async")
            print(".. \t Device Registered \n")
            registerServer()
        }
    }
    
    
    func handleServerRegisterMessage(message: JSON) {
        guard message != [] else { return }
        if let senderName = message["senderName"].string {
            if (senderName == serverName) {
                isServerRegister = true
                // reset and stop registerServerTimeoutId
                socketState = socketStateType.OPEN
                delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
                print("\n ON Async")
                print(".. \t Server Registered\n")
                delegate?.asyncReady()
                sendDataFromQueueToSocekt()
            }
        } else {
            registerServer()
        }
        
    }
    
    
    func handleSendACK(messageContent: JSON) {
        guard messageContent != [] else { print("..Message Content is empty") ;return }
        let msgId = messageContent["id"].int ?? -1
        let content: JSON = ["messageId": msgId]
        let msgIdStr = "\(content)"
        print("\n ON Async")
        print(".. Ack mesage content (to send) with id \n \(msgIdStr)\n")
        pushSendData(type: asyncMessageType.ACK.rawValue, content: msgIdStr)
    }
    
    
    
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\


// methods to help with socket
extension Async {
    
    // have peerId and device is not tegistered yet, so register Device
    func registerDevice() {
        print("\n ON Async")
        print(".. \t registering Device \n")
        var content: JSON = []
        if (peerId == 0) {
            content = ["appId": appId, "deviceId": deviceId, "renew": true]
        } else {
            content = ["appId": appId, "deviceId": deviceId, "refresh": true]
        }
        let contentStr = "\(content)"
        pushSendData(type: asyncMessageType.DEVICE_REGISTER.rawValue, content: contentStr)
    }
    
    // have peerId, device is registered, server is not, so register Server
    func registerServer() {
        print("\n ON Async")
        print(".. \t registering Server \n")
        let content: JSON = ["name": serverName]
        let contentStr = "\(content)"
        pushSendData(type: asyncMessageType.SERVER_REGISTER.rawValue, content: contentStr)
        
        registerServerTimeoutIdTimer = RepeatingTimer(timeInterval: TimeInterval(connectionRetryInterval))
        registerServerTimeoutIdTimer?.eventHandler = {
            self.self.retryToRegisterServer()
            self.registerServerTimeoutIdTimer?.suspend()
        }
        registerServerTimeoutIdTimer?.resume()
    }
    
    
    // data comes to be preapare to send
    // this will decide to send right away it or put in on Queue to send later
    public func pushSendData(type: Int, content: String) {
        if (socketState == socketStateType.OPEN) {
            sendData(type: type, content: content)
        } else {
            sendDataToQueue(type: type, content: content)
        }
    }
    
    
    // this method will send data through socket
    func sendData(type: Int, content: String?) {
        self.lastSentMessageTimeoutIdTimer?.suspend()
        DispatchQueue.global().async {
            self.lastSentMessageTime = Date()
            self.lastSentMessageTimeoutIdTimer = RepeatingTimer(timeInterval: TimeInterval(self.connectionCheckTimeout))
            self.lastSentMessageTimeoutIdTimer?.eventHandler = {
                if let lastSendMessageTimeBanged = self.lastSentMessageTime {
                    let elapsed = Date().timeIntervalSince(lastSendMessageTimeBanged)
                    let elapsedInt = Int(elapsed)
                    if (elapsedInt >= self.connectionCheckTimeout) {
                        DispatchQueue.main.async {
                            self.asyncSendPing()
                        }
                        self.lastSentMessageTimeoutIdTimer?.suspend()
                    }
                }
            }
            self.lastSentMessageTimeoutIdTimer?.resume()
        }
        
        if (socketState == socketStateType.OPEN) {
            var message: JSON
            if let cont = content {
                message = ["type": type, "content": cont]
            } else {
                message = ["type": type]
            }
            let messageStr: String = "\(message)"
            delegate?.asyncSendMessage(params: message)
            
            let compressedStr = String(messageStr.filter { !" \n\t\r".contains($0) })
            let strWithReturn = compressedStr.replacingOccurrences(of: "Ⓝ", with: "\n")
            let strWithSpace = strWithReturn.replacingOccurrences(of: "Ⓢ", with: " ")
            let strWithTab = strWithSpace.replacingOccurrences(of: "Ⓣ", with: "\t")
            
            print("\n ON Async")
            print("..this message sends through socket: \n \(strWithTab) \t\n")
            
            socket?.write(string: strWithTab)
        }
    }
    
    
    // this method will save data (that have to send) on a Queue, to send it later
    func sendDataToQueue(type: Int, content: String) {
        print("\n ON Async")
        print("..send data to queue \n")
        let obj = ["type": type, "content": content] as [String : Any]
        pushSendDataArr.append(obj)
    }
    
    
    // send data from queue to socket
    func sendDataFromQueueToSocekt() {
        for (i, item) in pushSendDataArr.enumerated().reversed() {
            if socketState == socketStateType.OPEN {
                let type: Int = item["type"] as! Int
                let content: String = item["content"] as! String
                sendData(type: type, content: content)
                pushSendDataArr.remove(at: i)
            }
        }
    }
    
    
    func checkIfSocketIsCloseOrNot() {
        DispatchQueue.main.async {
            if (!self.isSocketOpen) {
                let err: [String : Any] = ["errorCode": 4001, "errorMessage": "Can not open Socket!"]
                print("\n ON Async")
                print("..MyLog: Error: \(err). location: 'checkIfSocketIsCloseOrNot' func\n")
                self.delegate?.asyncError(errorCode: 4001, errorMessage: "Can not open Socket!", errorEvent: nil)
            } else {
                self.delegate?.asyncStateChanged(socketState: self.socketState.rawValue, timeUntilReconnect: 0, deviceRegister: self.isDeviceRegister, serverRegister: self.isServerRegister, peerId: self.peerId)
            }
        }
    }
    
    
    func connecntToSocket() {
        DispatchQueue.main.async {
            self.socket?.connect()
        }
    }
    
    
    @objc func retryToRegisterServer() {
        DispatchQueue.main.async {
            if (!self.isServerRegister) {
                self.registerServer()
            }
        }
    }
    
    
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\


// Public methods:
extension Async {
    
    // this will return Async State
    public func asyncGetAsyncState() -> String {
        return asyncState
    }
    
    // this will return peerId
    public func asyncGetPeerId() -> Int {
        return peerId
    }
    
    // this will return ServerName
    public func asyncGetServerName() -> String {
        return serverName
    }
    
    // this will set new name to ServerName
    public func asyncSetServerName(_ newServerName: String) {
        serverName = newServerName
    }
    
    // this will set new DeviceId
    public func asyncSetDeviceId (_ newDeviceId: String) {
        deviceId = newDeviceId
    }
    
    // this will prepare data to send ping through
    public func asyncSendPing() {
        sendData(type: 0, content: nil)
    }
    
    // this method will get content and prepare data to send
    public func asyncSend(type: Int, content: String, receivers: [Int], priority: Int, ttl: Int) {
        lastMessageId += 1
        let messageId = lastMessageId
        
        let msgJSON: JSON = ["content": content, "receivers": receivers, "priority": priority, "messageId": messageId, "ttl": messageTtl]
        let msgContentStr = "\(msgJSON)"
        pushSendData(type: type, content: msgContentStr)
    }
    
    // disconnect from socket
    public func asyncClose() {
        isDeviceRegister = false
        isServerRegister = false
        socketState = socketStateType.CLOSED
        delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
        socket?.disconnect()
    }
    
    // log out with this account and close socket
    public func asyncLogOut() {
        oldPeerId = peerId
        peerId = 0
        isServerRegister = false
        isDeviceRegister = false
        isSocketOpen = false
        pushSendDataArr = []
        registerServerTimeoutIdTimer?.suspend()
        socketState = socketStateType.CLOSED
        delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
        reconnectOnClose = false
        asyncClose()
    }
    
    // try to connect to socket again with my last peerId
    public func asyncReconnectSocket() {
        oldPeerId = peerId
        isDeviceRegister = false
        isSocketOpen = false
        registerServerTimeoutIdTimer?.suspend()
        socket?.connect()
    }
    
}








