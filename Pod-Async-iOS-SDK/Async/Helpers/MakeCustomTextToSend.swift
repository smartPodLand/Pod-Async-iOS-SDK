//
//  MakeCustomTextToSend.swift
//  FanapPodAsyncSDK
//
//  Created by Mahyar Zhiani on 3/22/1398 AP.
//  Copyright © 1398 Mahyar Zhiani. All rights reserved.
//

import Foundation


open class MakeCustomTextToSend {
    
    let textMessage: String
    
    public init(message: String) {
        self.textMessage = message
    }
    
    /*
     it's all about this 3 characters: 'space' , '\n', '\t'
     this function will put some freak characters instead of these 3 characters (inside the Message text content)
     because later on, the Async will eliminate from all these kind of characters to reduce size of the message that goes through socket,
     on there, we will replace them with the original one;
     so now we don't miss any of these 3 characters on the Test Message, but also can eliminate all extra characters...
     */
    public func replaceSpaceEnterWithSpecificCharecters() -> String {
        var returnStr = ""
        for c in textMessage {
            if (c == " ") {
                returnStr.append("Ⓢ")
            } else if (c == "\n") {
                returnStr.append("Ⓝ")
            } else if (c == "\t") {
                returnStr.append("Ⓣ")
            } else {
                returnStr.append(c)
            }
        }
        return returnStr
    }
    
    
    
    
    public func removeSpecificCharectersWithSpace() -> String {
        
        // these 4 lines are to remove some characters (like: space, \n , \t) exept tho ones that are in the message text context
        let compressedStr = String(textMessage.filter { !" \n\t\r".contains($0) })
        let strWithReturn = compressedStr.replacingOccurrences(of: "Ⓝ", with: "\n")
        let strWithSpace = strWithReturn.replacingOccurrences(of: "Ⓢ", with: " ")
        let strWithTab = strWithSpace.replacingOccurrences(of: "Ⓣ", with: "\t")
        
        return strWithTab
    }
    
    
}
