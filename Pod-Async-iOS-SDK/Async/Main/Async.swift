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
    
    var socketAddress:          String      // socket address
    var serverName:             String      // server to register on
    var deviceId:               String      // the user current device id
    
    var appId:                  String      //
    var peerId:                 Int         // pper id of the user on the server
    var messageTtl:             Int         //
    var reconnectOnClose:       Bool        // should i try to reconnet the socket whenever socket is close?
    var connectionRetryInterval:Int         // how many times to try to connet the socket
    var maxReconnectTimeInterval: Int
    
    // MARK: - Async initializer
    public init(socketAddress:      String,
                serverName:         String,
                deviceId:           String,
                appId:              String?,
                peerId:             Int?,
                messageTtl:         Int?,
                connectionRetryInterval: Int?,
                maxReconnectTimeInterval: Int?,
                reconnectOnClose:   Bool?) {
        
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
        
        if let maxReconnectTime = maxReconnectTimeInterval {
            self.maxReconnectTimeInterval = maxReconnectTime
        } else {
            self.maxReconnectTimeInterval = 60
        }
        
    }
    
    
    var oldPeerId:          Int?
    var isSocketOpen        = false
    var isDeviceRegister    = false
    var isServerRegister    = false
    
    var socketState         = socketStateType.CONNECTING
//    private var asyncState          = ""
    
    //    private var registerServerTimeoutId: Int        = 0
    //    private var registerDeviceTimeoutId: Int        = 0
    var checkIfSocketHasOpennedTimeoutId:   Int = 0
    var socketReconnectRetryInterval:       Int = 0
    var socketReconnectCheck:               Int = 0
    
    var lastMessageId           = 0
    var retryStep:      Double  = 1
    //    var asyncReadyTimeoutId
    var pushSendDataArr         = [[String: Any]]()
    
    //    var waitForSocketToConnectTimeoutId: Int
    var wsConnectionWaitTime:           Int = 5
    var connectionCheckTimeout:         Int = 10
    
    
    // used to close socket if needed (func handleIfNeedsToCloseTheSocket)
    var lastReceivedMessageTime:    Date?
    var lastReceivedMessageTimer:   RepeatingTimer? {
        didSet {
            
            self.lastReceivedMessageTimer?.suspend()
            DispatchQueue.global().async {
                self.lastReceivedMessageTimer?.eventHandler = {
                    if let lastReceivedMessageTimeBanged = self.lastReceivedMessageTime {
                        let elapsed = Date().timeIntervalSince(lastReceivedMessageTimeBanged)
                        let elapsedInt = Int(elapsed)
                        if (elapsedInt >= self.connectionCheckTimeout) {
                            DispatchQueue.main.async {
                                self.socket?.disconnect()
                            }
                            self.lastReceivedMessageTimer?.suspend()
                        }
                    }
                }
                self.lastReceivedMessageTimer?.resume()
            }
            
        }
    }
    
    
    // used to live the socket connection (func sendData)
    var lastSentMessageTime:    Date?
    var lastSentMessageTimer:   RepeatingTimer? {
        didSet {
            
            self.lastSentMessageTimer?.suspend()
            DispatchQueue.global().async {
                self.lastSentMessageTime = Date()
                self.lastSentMessageTimer?.eventHandler = {
                    if let lastSendMessageTimeBanged = self.lastSentMessageTime {
                        let elapsed = Date().timeIntervalSince(lastSendMessageTimeBanged)
                        let elapsedInt = Int(elapsed)
                        if (elapsedInt >= self.connectionCheckTimeout) {
                            DispatchQueue.main.async {
                                self.asyncSendPing()
                            }
                            if let _ = self.lastSentMessageTimer {
                                self.lastSentMessageTimer?.suspend()
                            }
                        }
                    }
                }
                self.lastSentMessageTimer?.resume()
            }
            
        }
    }
    
    
    
//    var socketRealTimeStatusInterval:   RepeatingTimer?
    
    var retryToConnectToSocketTimer = RepeatingTimer(timeInterval: 0) {
        didSet {
            
            retryToConnectToSocketTimer.eventHandler = {
                if (self.retryStep < Double(self.maxReconnectTimeInterval)) {
                    self.retryStep = self.retryStep * 2
                } else {
                    self.retryStep = Double(self.maxReconnectTimeInterval)
                }
                DispatchQueue.main.async {
                    log.verbose("try to connect to the socket on the main threat. maxReconnectTimeInterval = \(self.maxReconnectTimeInterval), NextRetryStep = \(self.retryStep)", context: "Async")
                    
                    self.socket?.connect()
                    self.retryToConnectToSocketTimer.suspend()
                }
            }
            retryToConnectToSocketTimer.resume()
            
        }
    }
    
    
    // use to check if we can initial socket connection or not, at the start creation of Async (func startTimers)
    var checkIfSocketHasOpennedTimer:  RepeatingTimer? {
        didSet {
            
            checkIfSocketHasOpennedTimer?.eventHandler = {
                self.checkIfSocketIsCloseOrNot()
                self.checkIfSocketHasOpennedTimer?.suspend()
            }
            checkIfSocketHasOpennedTimer?.resume()
            
        }
    }
    
//    var socketReconnectRetryIntervalTimer:      RepeatingTimer?
//    var socketReconnectCheckTimer:              RepeatingTimer?
    
    var registerServerTimer: RepeatingTimer? {
        didSet {
            
            registerServerTimer?.eventHandler = {
                self.self.retryToRegisterServer()
                self.registerServerTimer?.suspend()
            }
            registerServerTimer?.resume()
            
        }
    }
    
    var socket: WebSocket?
    
}



