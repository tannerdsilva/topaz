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
	func relativeShortTimeString(to nowTime:DBUX.Date = DBUX.Date()) -> String {
		var time = ceil(self.timeIntervalSince(nowTime))
		if (time > 0) {
			switch time {
			case 0..<60:
				return "In \(Int(time))s"
			case 60..<3600:
				return "In \(Int(time/60))m"
			case 3600..<86399:
				return "In \(Int(time/3600))h"
			default:
				return "In \(Int(time/86400))d"
			}
		} else {
			time = abs(time)
			switch time {
			case 0..<60:
				return "\(Int(time))s"
			case 60..<3600:
				return "\(Int(time/60))m"
			case 3600..<86399:
				return "\(Int(time/3600))h"
			default:
				return "\(Int(time/86400))d"
			}
		}
	}
}
