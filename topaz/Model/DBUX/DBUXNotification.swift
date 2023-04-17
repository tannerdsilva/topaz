//
//  DBUXNotification.swift
//  topaz
//
//  Created by Tanner Silva on 4/17/23.
//

import Foundation

extension DBUX {
	enum Notification {
		case currentUserProfileUpdated		// fired when a new profile is written for the current user
		case currentUserFollowsUpdated
	}
}
