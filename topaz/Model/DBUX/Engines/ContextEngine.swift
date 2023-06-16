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
		
		// all of the configurable preferences that a user may specify
		struct UserPreferences:Codable {
			struct Appearance:Codable {
				enum NamePriorityPreference:UInt8, Codable {
					case fullNamePreferred = 0
					case usernamePreferred = 1
				}
				var alwaysShowEventActions = true
				var displayEmojisInNames = true
				var namePriorityPreference = NamePriorityPreference.usernamePreferred
				var doNotShowIdenticalNames = false
			}
			var appearanceSettings = Appearance()
		}
		
		typealias NotificationType = DBUX.Notification
		static let name = "context-engine.mdb"
		static let deltaSize = SizeMode.fixed(size_t(1e+6))
		static let maxDBs:MDB_dbi = 1
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher:Dispatcher<NotificationType>
		let base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger

		enum Contexts:String, MDB_convertible {
			case badgeStatus = "badge_status" // ViewBadgeStatus
			case viewMode = "view_mode" // ViewMode
			case timelineAnchor = "timeline_anchor" // TimelineAnchor
			case timelineRepliesToggleEnabled = "timeline_replies_toggle_enabled" // Bool
			case userPreferences = "user_prefs"	//UserPreferences
		}

		fileprivate let encoder:JSONEncoder
		fileprivate let userContext:Database

		required init(base:URL, env:QuickLMDB.Environment, keyPair:nostr.KeyPair, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.base = base
			self.env = env
			self.pubkey = keyPair.pubkey
			self.logger = Logger(label: "context-engine.mdb")
			let newTrans = try Transaction(env, readOnly:false)
			let context = try env.openDatabase(named:nil, flags:[.create], tx:newTrans)
			self.userContext = context
			
			self.encoder = JSONEncoder()
			let decoder = JSONDecoder()
			
			// get the badge status
			do {
				let decoded = try decoder.decode(DBUX.ViewBadgeStatus.self, from:try context.getEntry(type:Data.self, forKey:Contexts.badgeStatus, tx:newTrans)!)
				_badgeStatus = Published(wrappedValue:decoded)
			} catch LMDBError.notFound {
				let newBadgeStatus = DBUX.ViewBadgeStatus.defaultViewBadgeStatus()
				_badgeStatus = Published(wrappedValue:newBadgeStatus)
				try context.setEntry(value:try encoder.encode(newBadgeStatus), forKey:Contexts.badgeStatus, tx:newTrans)
			}

			// get the view mode
			do {
				let decoded = try decoder.decode(DBUX.ViewMode.self, from:try context.getEntry(type:Data.self, forKey:Contexts.viewMode, tx:newTrans)!)
				_viewMode = Published(wrappedValue:decoded)
			} catch LMDBError.notFound {
				let newViewMode:DBUX.ViewMode = .home
				_viewMode = Published(wrappedValue:newViewMode)
				try context.setEntry(value:encoder.encode(newViewMode), forKey:Contexts.viewMode, tx:newTrans)
			}

			// get the timeline anchor
			do {
				let decoded = try context.getEntry(type:DBUX.DatedNostrEventUID.self, forKey:Contexts.timelineAnchor, tx:newTrans)
				_timelineAnchor = Published(wrappedValue:decoded)
			} catch LMDBError.notFound {
				_timelineAnchor = Published(wrappedValue:nil)
			}
			
			do {
				let getBool = try context.getEntry(type:Bool.self, forKey:Contexts.timelineRepliesToggleEnabled, tx:newTrans)!
				_timelineRepliesToggleEnabled = Published(wrappedValue:getBool)
			} catch LMDBError.notFound {
				_timelineRepliesToggleEnabled = Published(wrappedValue:false)
			}
			
			do {
				let getPrefData = try context.getEntry(type:Data.self, forKey:Contexts.userPreferences, tx:newTrans)!
				let decoded = try decoder.decode(UserPreferences.self, from:getPrefData)
				_userPreferences = Published(wrappedValue: decoded)
			} catch LMDBError.notFound {
				_userPreferences = Published(wrappedValue:UserPreferences())
			}

			try newTrans.commit()
		}

		@MainActor @Published var timelineAnchor:DBUX.DatedNostrEventUID? {
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
		@MainActor @Published var badgeStatus:ViewBadgeStatus {
			willSet {
				let encoded = try! encoder.encode(newValue)
				try! self.userContext.setEntry(value:encoded, forKey:Contexts.badgeStatus, tx:nil)
				self.logger.debug("successfully updated badge status.", metadata:["badgeStatus": "\(newValue)"])
			}
		}

		@MainActor @Published var viewMode:ViewMode {
			willSet {
				let encoded = try! encoder.encode(newValue)
				try! self.userContext.setEntry(value:encoded, forKey:Contexts.viewMode, tx:nil)
				self.logger.debug("successfully updated view mode.", metadata:["viewMode": "\(newValue)"])
			}
		}
		
		@MainActor @Published var timelineRepliesToggleEnabled:Bool {
			willSet {
				try! self.userContext.setEntry(value:newValue, forKey:Contexts.timelineRepliesToggleEnabled, tx:nil)
				self.logger.debug("successfully updated toggle reply state.", metadata:["isEnabled": "\(newValue)"])
			}
		}
		
		@MainActor @Published var userPreferences:UserPreferences {
			willSet {
				let encoded = try! encoder.encode(newValue)
				try! self.userContext.setEntry(value:encoded, forKey:Contexts.userPreferences, tx:nil)
				self.logger.debug("successfully updated user preferences.")
			}
		}
	}
}
