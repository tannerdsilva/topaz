//
//  ViewModels.swift
//  topaz
//
//  Created by Tanner Silva on 4/14/23.
//

import Foundation
import QuickLMDB

extension DBUX {
	/// stores the primary root view that the user is currently viewing
	enum ViewMode:Int, MDB_convertible, Codable {
		case home = 0
		case notifications = 1
		case dms = 2
		case search = 3
		case profile = 4
	}
	
	// stores the primary tab viwe badge status for the user
	struct ViewBadgeStatus:Codable {
		var homeBadge:Bool
		var notificationsBadge:Bool
		var dmsBadge:Bool
		var searchBadge:Bool
		var profileBadge:Bool
		
		fileprivate init(homeBadge:Bool, notificationsBadge:Bool, dmsBadge:Bool, searchBadge:Bool, profileBadge:Bool) {
			self.homeBadge = homeBadge
			self.notificationsBadge = notificationsBadge
			self.dmsBadge = dmsBadge
			self.searchBadge = searchBadge
			self.profileBadge = profileBadge
		}
		
		static func defaultViewBadgeStatus() -> ViewBadgeStatus {
			return Self(homeBadge:false, notificationsBadge: false, dmsBadge: false, searchBadge: false, profileBadge: false)
		}
	}
}
