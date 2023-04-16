//
//  ContextEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/14/23.
//

import Foundation
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms

extension DBUX {
	class ContextEngine:ObservableObject, ExperienceEngine {
		static let name = "context-engine.mdb"
		static let deltaSize = size_t(35e10)
		static let maxDBs:MDB_dbi = 1
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger

		enum Contexts:String, MDB_convertible {
			case badgeStatus = "badge_status" // ViewBadgeStatus
			case viewMode = "view_mode" // ViewMode
			case timelineAnchor = "timeline_anchor" // TimelineAnchor
		}

		fileprivate let encoder:JSONEncoder
		fileprivate let userContext:Database

		required init(base:URL, env:QuickLMDB.Environment, publicKey pubkey:nostr.Key) throws {
			self.base = base
			self.env = env
			self.pubkey = pubkey
			self.logger = Logger(label: "context-engine.mdb")
			let newTrans = try Transaction(env, readOnly:false)
			let context = try env.openDatabase(named:nil, flags:[.create], tx:newTrans)
			self.userContext = context
			
			self.encoder = JSONEncoder()
			let decoder = JSONDecoder()
			
			// get the badge status
			do {
				let decoded = try decoder.decode(DBUX.ViewBadgeStatus.self, from:try context.getEntry(type:Data.self, forKey:Contexts.badgeStatus, tx:newTrans)!)
				_badgeStatus = Published(initialValue:decoded)
			} catch LMDBError.notFound {
				let newBadgeStatus = DBUX.ViewBadgeStatus.defaultViewBadgeStatus()
				_badgeStatus = Published(initialValue:newBadgeStatus)
				try context.setEntry(value:try encoder.encode(newBadgeStatus), forKey:Contexts.badgeStatus, tx:newTrans)
			}

			// get the view mode
			do {
				let decoded = try decoder.decode(DBUX.ViewMode.self, from:try context.getEntry(type:Data.self, forKey:Contexts.viewMode, tx:newTrans)!)
				_viewMode = Published(initialValue:decoded)
			} catch LMDBError.notFound {
				let newViewMode:DBUX.ViewMode = .home
				_viewMode = Published(initialValue:newViewMode)
				try context.setEntry(value:encoder.encode(newViewMode), forKey:Contexts.viewMode, tx:newTrans)
			}

			// get the timeline anchor
			do {
				let decoded = try context.getEntry(type:DBUX.DatedNostrEventUID.self, forKey:Contexts.timelineAnchor, tx:newTrans)
				_timelineAnchor = Published(initialValue:decoded)
			} catch LMDBError.notFound {
				_timelineAnchor = Published(initialValue:nil)
			}
			try newTrans.commit()
		}

		@Published var timelineAnchor:DBUX.DatedNostrEventUID? {
			willSet {
				if let hasVal = newValue {
					try! self.userContext.setEntry(value:hasVal, forKey:Contexts.timelineAnchor, tx:nil)
				}
			}
		}
		func getTimelineAnchor() throws -> DBUX.DatedNostrEventUID? {
			do {
				return try self.userContext.getEntry(type:DBUX.DatedNostrEventUID.self, forKey:Contexts.timelineAnchor, tx:nil)
			} catch LMDBError.notFound {
				return nil
			}
		}

		// tab bar related items
		@Published var badgeStatus:ViewBadgeStatus {
			willSet {
				let encoder = JSONEncoder()
				let encoded = try! encoder.encode(newValue)
				try! self.userContext.setEntry(value:encoded, forKey:Contexts.badgeStatus, tx:nil)
				self.logger.debug("successfully updated badge status.", metadata:["badgeStatus": "\(newValue)"])
			}
		}

		@Published var viewMode:ViewMode {
			willSet {
				let encoder = JSONEncoder()
				let encoded = try! encoder.encode(newValue)
				try! self.userContext.setEntry(value:encoded, forKey:Contexts.viewMode, tx:nil)
				self.logger.debug("successfully updated view mode.", metadata:["viewMode": "\(newValue)"])
			}
		}
	}
}
