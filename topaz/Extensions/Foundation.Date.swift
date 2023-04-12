//
//  Date.swift
//  topaz
//
//  Created by Tanner Silva on 3/12/23.
//

import Foundation

extension Date {
	func relativeShortTimeString(to nowTime:Date = Date()) -> String {
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