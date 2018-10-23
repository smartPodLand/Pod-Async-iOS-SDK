//
//  WebSocketImplementation.swift
//  Async
//
//  Created by Mahyar Zhiani on 7/23/1397 AP.
//  Copyright © 1397 Mahyar Zhiani. All rights reserved.
//

import Foundation
import Starscream

// implement websocket delegate methods
extension Async: WebSocketDelegate {
    
    public func websocketDidConnect(socket: WebSocketClient) {
        handleOnOppendSocket()
    }
    
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        handleOnClosedSocket()
        print("\n ON Async")
        print(".. \t socket closed error = \(error ?? "??" as! Error)\n")
    }
    
    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        handleOnRecieveMessage(messageRecieved: text)
    }
    
    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        
    }
    
}



