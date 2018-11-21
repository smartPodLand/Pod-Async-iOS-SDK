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
import SwiftyBeaver

public let log = LogWithSwiftyBeaver().log

// this is the Async class that will handles Asynchronous messaging
public class Async {
    
    public weak var delegate: AsyncDelegates?
    
    
    private var socketAddress:          String      // socket address
    private var serverName:             String      // server to register on
    private var deviceId:               String      // the user current device id
    
    private var appId:                  String      //
    private var peerId:                 Int         // pper id of the user on the server
    private var messageTtl:             Int         //
    private var reconnectOnClose:       Bool        // should i try to reconnet the socket whenever socket is close?
    private var connectionRetryInterval:Int         // how many times to try to connet the socket
    
    // MARK: - Async initializer
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
    
    var t = RepeatingTimer(timeInterval: 0)
    
    var checkIfSocketHasOpennedTimeoutIdTimer:  RepeatingTimer?
    var socketReconnectRetryIntervalTimer:      RepeatingTimer?
    var socketReconnectCheckTimer:              RepeatingTimer?
    
    var registerServerTimeoutIdTimer: RepeatingTimer?
    
    var socket: WebSocket?
    
    // MARK: - Create Socket Connection
    /*
     this function will open a soccket connection to the server
    */
    public func createSocket() {
        var request = URLRequest(url: URL(string: socketAddress)!)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
        startTimers()
        socket?.connect()
    }
    
    // MARK: - Instantiate Timer
    func startTimers() {
        checkIfSocketHasOpennedTimeoutIdTimer = RepeatingTimer(timeInterval: 65)
        checkIfSocketHasOpennedTimeoutIdTimer?.eventHandler = {
            self.checkIfSocketIsCloseOrNot()
            self.checkIfSocketHasOpennedTimeoutIdTimer?.suspend()
        }
        checkIfSocketHasOpennedTimeoutIdTimer?.resume()
    }
    
    
    
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\


// MARK: - Methods on socket connection
extension Async {
    
    // MARK: - Socket Oppend
    /*
    when socket is connected, this function will trigger
    */
    func handleOnOppendSocket() {
        log.verbose("Handle On Oppend Socket", context: "Async")
        
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
    
    
    // MARK: - Socket Closed
    /*
    when socket is closed, this function will trigger
    this function will reset some variables such as: 'isSocketOpen', 'isDeviceRegister', 'socketState', but keep 'oldPeerId'
    then sends 'asyncStateChanged' delegate
    after that will try to connect to socket again (if 'reconnectOnClose' has set 'true' by the client)
    */
    func handleOnClosedSocket() {
        log.verbose("Handle On Closed Socket", context: "Async")
        
        isSocketOpen = false
        isDeviceRegister = false
        oldPeerId = peerId
        
        socketState = socketStateType.CLOSED
        
        delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
        delegate?.asyncDisconnect()
        
        // here, we try to connect to the socket on specific period of time
        if (reconnectOnClose) {
            socketState = socketStateType.CLOSED
            delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: Int(retryStep), deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
            
            t = RepeatingTimer(timeInterval: retryStep)
            t.eventHandler = {
                if (self.retryStep < 60) {
                    self.retryStep = self.retryStep * 2
                }
                DispatchQueue.main.async {
                    log.verbose("try to connect to the socket on the main threat", context: "Async")
                    
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
    
    // MARK: - Message Recieved
    /*
     when a message recieves from the socket connection, this function will trigger
     base on the type of the message, we do sth
     types:
     0: PING
     1: SERVER_REGISTER
     2: DEVICE_REGISTER
     3: MESSAGE
     4: MESSAGE_ACK_NEEDED
     5: ACK
     6: ERROR_MESSAGE
    */
    func handleOnRecieveMessage(messageRecieved: String) {
        
        lastReceivedMessageTime = Date()
        
        if let dataFromMsgString = messageRecieved.data(using: .utf8, allowLossyConversion: false) {
            do {
                let msg = try JSON(data: dataFromMsgString)
                
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
                log.error("can not convert incoming String Message to JSON", context: "Async")
            }
        } else {
            log.error("the message comming from server, is not on the correct format!!", context: "Async")
        }
        
        // set timer to check if needed to close the socket!
        handleIfNeedsToCloseTheSocket()
    }
    
    // Close Socket connection if needed
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
    
    // MARK: - Sends Ping Message
    /*
     this is the function that sends Ping Message to the server
     */
    func handlePingMessage(message: JSON) {
        if (!isDeviceRegister) {
            if (message["id"].int != nil) {
                registerDevice()
            } else {
                delegate?.asyncError(errorCode: 4003, errorMessage: "Device Id is not present!", errorEvent: nil)
            }
        }
        
    }
    
    // MARK: - Register Device
    /*
     device registered message comes from server, and in its content, it has 'peerId' of the user
     we set 'isDeviceRegister' to 'true', and set 'peerId'
     and also send 'asyncStateChanged' to delegate
    */
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
            log.info("Device has Registered successfully", context: "Async")
            
            registerServer()
        }
    }
    
    // MARK: - Register Server
    /*
     Server registered message comes from server
     we set 'isServerRegister' to 'true', and set 'socketState' to 'OPEN' state
     and then send 'asyncStateChanged' to delegate, and of course 'asyncReady'
     */
    func handleServerRegisterMessage(message: JSON) {
        guard message != [] else { return }
        if let senderName = message["senderName"].string {
            if (senderName == serverName) {
                isServerRegister = true
                // reset and stop registerServerTimeoutId
                socketState = socketStateType.OPEN
                delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
                
                log.info("Server has Registered successfully", context: "Async")
                
                delegate?.asyncReady()
                sendDataFromQueueToSocekt()
            }
        } else {
            registerServer()
        }
        
    }
    
    // MARK: - Send ACK
    /*
     try to send ACk to server for the message that comes from server and it need ACK for this message
     */
    func handleSendACK(messageContent: JSON) {
        guard messageContent != [] else {
            log.warning("Message Content is empty", context: "Async")
            return
        }
        let msgId = messageContent["id"].int ?? -1
        let content: JSON = ["messageId": msgId]
        let msgIdStr = "\(content)"
        log.info("try to send Ack message with id: \(msgIdStr)", context: "Async")
        
        pushSendData(type: asyncMessageType.ACK.rawValue, content: msgIdStr)
    }
    
    
    
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\


// methods to help with socket
extension Async {
    
    
    // MARK: - make Device Register Message
    /*
     this is the function that will make message to Register Device
     here, we have PeerId, and the next step is to Register Device
     */
    func registerDevice() {
        log.info("make Device Register Message", context: "Async")
        
        var content: JSON = []
        if (peerId == 0) {
            content = ["appId": appId, "deviceId": deviceId, "renew": true]
        } else {
            content = ["appId": appId, "deviceId": deviceId, "refresh": true]
        }
        let contentStr = "\(content)"
        pushSendData(type: asyncMessageType.DEVICE_REGISTER.rawValue, content: contentStr)
    }
    
    // MARK: - make Server Register Message
    /*
     this is the function that will make message to Register Server
     here, we have PeerId, and the Device Registered befor,
     and the next step is to Register Server
    */
    func registerServer() {
        log.info("make Server Register Message", context: "Async")
        
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
    
    // MARK: - prepare data to Send Message
    /*
     data comes here to be preapare to send
     this functin will decide to send it right away or put in on a Queue to send it later (based on the state of the socket connection)
    */
    public func pushSendData(type: Int, content: String) {
        if (socketState == socketStateType.OPEN) {
            sendData(type: type, content: content)
        } else {
            sendDataToQueue(type: type, content: content)
        }
    }
    
    // MARK: - Send Message logically
    /*
     this method will send data through socket connection logically.
     first of all, set a timer to keep the socket connection alive;
     then if the socket connection state was "OPEN", send the data
     */
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
            
            // these 4 lines are to remove some characters (like: space, \n , \t) exept tho ones that are in the message text context
            let compressedStr = String(messageStr.filter { !" \n\t\r".contains($0) })
            let strWithReturn = compressedStr.replacingOccurrences(of: "Ⓝ", with: "\n")
            let strWithSpace = strWithReturn.replacingOccurrences(of: "Ⓢ", with: " ")
            let strWithTab = strWithSpace.replacingOccurrences(of: "Ⓣ", with: "\t")
            
            log.info("this message sends through socket: \n \(strWithTab)", context: "Async")
            
            socket?.write(string: strWithTab)
        }
    }
    
    // MARK: - Hold Messages (that have to be send) on a queue
    /*
     this method will hold messages to send them later.
     (this will contain messges on a queue)
     */
    func sendDataToQueue(type: Int, content: String) {
        log.info("send data to queue", context: "Async")
        
        let obj = ["type": type, "content": content] as [String : Any]
        pushSendDataArr.append(obj)
    }
    
    // MARK: - send data from queue to Send function
    /*
     this method will get the messages from queue and pass them to SendData function to send them
     after that, it will remove that message the queue
     */
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
    
    // MARK: - Check socket connection if it's Closed or not
    /*
     this method will check the socket connection if it's Open or not,
     and then send the socket status to delegate
     */
    func checkIfSocketIsCloseOrNot() {
        DispatchQueue.main.async {
            if (!self.isSocketOpen) {
                let err: [String : Any] = ["errorCode": 4001, "errorMessage": "Can not open Socket!"]
                
                log.error("\(err)", context: "Async")
                
                self.delegate?.asyncError(errorCode: 4001, errorMessage: "Can not open Socket!", errorEvent: nil)
            } else {
                self.delegate?.asyncStateChanged(socketState: self.socketState.rawValue, timeUntilReconnect: 0, deviceRegister: self.isDeviceRegister, serverRegister: self.isServerRegister, peerId: self.peerId)
            }
        }
    }
    
    // MARK: - Connect to Server
    /*
     this method will try to connect to the server, by oppening the socket connection
     */
    func connecntToSocket() {
        DispatchQueue.main.async {
            self.socket?.connect()
        }
    }
    
    // MARK: - Retry Server Registeration
    /*
     this method will try to do the 'Server Register' functionality
     */
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
    
    // MARK: - Get Async Status
    /*
     this method will return Async State (the value inside 'asyncState' property)
     */
    public func asyncGetAsyncState() -> String {
        return asyncState
    }
    
    // MARK: - Get PeerId
    /*
     this method will return peerId (the value inside 'peerId' property)
     */
    public func asyncGetPeerId() -> Int {
        return peerId
    }
    
    // MARK: - Get ServerName
    /*
     this method will return ServerName (the value inside 'ServerName' property)
     */
    public func asyncGetServerName() -> String {
        return serverName
    }
    
    // MARK: - Set ServerName
    /*
     this method will set a new name to ServerName
     */
    public func asyncSetServerName(_ newServerName: String) {
        serverName = newServerName
    }
    
    // MARK: - Set DeviceId
    /*
     this method will set new DeviceId
     */
    public func asyncSetDeviceId (_ newDeviceId: String) {
        deviceId = newDeviceId
    }
    
    // MARK: - Send Async Ping
    /*
     this method will send ping message throught Async
     */
    public func asyncSendPing() {
        sendData(type: 0, content: nil)
    }
    
    // MARK: - Send Async Message
    /*
     this method will get content and prepare the data inside that to send
     */
    public func asyncSend(type: Int, content: String, receivers: [Int], priority: Int, ttl: Int) {
        lastMessageId += 1
        let messageId = lastMessageId
        
        let msgJSON: JSON = ["content": content, "receivers": receivers, "priority": priority, "messageId": messageId, "ttl": messageTtl]
        let msgContentStr = "\(msgJSON)"
        pushSendData(type: type, content: msgContentStr)
    }
    
    // MARK: - Disconnect from socket
    /*
     this method will disconnect Async from socket
     */
    public func asyncClose() {
        isDeviceRegister = false
        isServerRegister = false
        socketState = socketStateType.CLOSED
        delegate?.asyncStateChanged(socketState: socketState.rawValue, timeUntilReconnect: 0, deviceRegister: isDeviceRegister, serverRegister: isServerRegister, peerId: peerId)
        socket?.disconnect()
    }
    
    // MARK: - Log Out
    /*
     this method will log out the user with this account and then will close the socket
     */
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
    
    // MARK: - Reconnect socket
    /*
     this method will try to connect to socket again with my last peerId
     */
    public func asyncReconnectSocket() {
        oldPeerId = peerId
        isDeviceRegister = false
        isSocketOpen = false
        registerServerTimeoutIdTimer?.suspend()
        socket?.connect()
    }
    
}








