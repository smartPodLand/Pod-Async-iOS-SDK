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
     
    // MARK: - Async initializer
    public init(socketAddress:      String,
                serverName:         String,
                deviceId:           String,
                appId:              String?,
                peerId:             Int?,
                messageTtl:         Int?,
                connectionRetryInterval: Int?,
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
    
}



