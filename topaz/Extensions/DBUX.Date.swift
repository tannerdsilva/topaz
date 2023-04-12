//
//  DBUX.Date.swift
//  topaz
//
//  Created by Tanner Silva on 4/11/23.
//

import Foundation

extension DBUX.Date {
	init() {
		self.init(Date())
	}
	internal init(_ date:Date) {
		self.rawVal = date.timeIntervalSinceReferenceDate
	}
	internal func exportDate() -> Date {
		return Date(timeIntervalSinceReferenceDate:self.rawVal)
	}
}
