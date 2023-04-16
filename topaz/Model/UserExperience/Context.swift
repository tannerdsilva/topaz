//
//  Context.swift
//  topaz
//
//  Created by Tanner Silva on 3/17/23.
//

import Foundation
import QuickLMDB

/*extension UE {
	// user context
	// - stores information about the current state of the user environment. this includes things such as notification badges, sync times with relays, etc
	// - the stuff that is stored in here is not metadata that a user should ever be concerned with managing directly. this is mostly a place for the topaz app to store relevant information about the user's current state
	class Context:ObservableObject {
		static let logger = Topaz.makeDefaultLogger(label:"ue-context")
		enum Contexts:String, MDB_convertible {
			case badgeStatus = "badge_status" // ViewBadgeStatus
			case viewMode = "view_mode" // ViewMode
		}

		// tab bar related items
		@Published var badgeStatus:DBUX.ViewBadgeStatus {
			willSet {
				let encoder = JSONEncoder()
				let encoded = try! encoder.encode(newValue)
				try! self.userContext.setEntry(value:encoded, forKey:Contexts.badgeStatus, tx:nil)
				Self.logger.debug("successfully updated badge status.", metadata:["badgeStatus": "\(newValue)"])
			}
		}

		@Published var viewMode:DBUX.ViewMode {
			willSet {
				let encoder = JSONEncoder()
				let encoded = try! encoder.encode(newValue)
				try! self.userContext.setEntry(value:encoded, forKey:Contexts.viewMode, tx:nil)
				Self.logger.debug("successfully updated view mode.", metadata:["viewMode": "\(newValue)"])
			}
		}
		
		fileprivate let env:QuickLMDB.Environment
		fileprivate let encoder:JSONEncoder
		fileprivate let userContext:Database

		// initializes the user context database with a valid read/write transaction
		init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			self.env = env
			let context = try env.openDatabase(named:Databases.userContext.rawValue, flags:[.create], tx:subTrans)
			self.userContext = context
			let encoder = JSONEncoder()
			let decoder = JSONDecoder()
			self.encoder = encoder

			// get the badge status
			do {
				let decoded = try decoder.decode(DBUX.ViewBadgeStatus.self, from:try context.getEntry(type:Data.self, forKey:Contexts.badgeStatus, tx:subTrans)!)
				_badgeStatus = Published(wrappedValue:decoded)
			} catch LMDBError.notFound {
				let newBadgeStatus = DBUX.ViewBadgeStatus.defaultViewBadgeStatus()
				_badgeStatus = Published(wrappedValue:newBadgeStatus)
				try context.setEntry(value:try encoder.encode(newBadgeStatus), forKey:Contexts.badgeStatus, tx:subTrans)
			}

			// get the view mode
			do {
				let decoded = try decoder.decode(DBUX.ViewMode.self, from:try context.getEntry(type:Data.self, forKey:Contexts.viewMode, tx:subTrans)!)
				_viewMode = Published(initialValue:decoded)
			} catch LMDBError.notFound {
				let newViewMode:DBUX.ViewMode = .home
				_viewMode = Published(initialValue:newViewMode)
				try context.setEntry(value:encoder.encode(newViewMode), forKey:Contexts.viewMode, tx:subTrans)
			}
			try subTrans.commit()
		}
	}
	
}
*/
