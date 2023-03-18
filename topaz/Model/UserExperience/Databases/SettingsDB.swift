//
//  SettingsDB.swift
//  topaz
//
//  Created by Tanner Silva on 3/17/23.
//

import Foundation
import QuickLMDB

extension UE {
	// UserSettings
	// - stores information about the user's preferences
	class Settings:ObservableObject {
		
		// initializes the settings database with a valid read/write transaction
		init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			try subTrans.commit()
		}
	}
}
