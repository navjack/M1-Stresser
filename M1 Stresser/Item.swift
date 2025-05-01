//
//  Item.swift
//  M1 Stresser
//
//  Created by Jack Mangano on 5/1/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
