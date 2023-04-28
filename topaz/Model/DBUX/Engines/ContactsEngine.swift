//
//  ContactsEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/14/23.
//

import struct Foundation.URL
import struct Darwin.size_t
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms

extension DBUX {
	// following related
	/// this database stores the list of users that the user is following
	class FollowsEngine:SharedExperienceEngine {

		let dispatcher: Dispatcher<DBUX.Notification>
		typealias NotificationType = DBUX.Notification
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger

		enum Databases:String {
			case pubkey_refreshDate = "pubkey_refreshDate"
			case user_following = "pubkey_follows"
		}
	
		let pubkey_date:Database			// stores the last time that the user profile information was updated.			[nostr.Key:DBUX.Date]
		let pubkey_following:Database		// stores the list of pubkeys that the user is following						[nostr.Key:nostr.Key?] * DUP * (value will be \0 if an account follows nobody)

		required init(env: QuickLMDB.Environment, publicKey: nostr.Key, dispatcher: Dispatcher<DBUX.Notification>) throws {
			self.dispatcher = dispatcher
			let newTrans = try Transaction(env, readOnly:false)
			self.pubkey_date = try env.openDatabase(named:Databases.pubkey_refreshDate.rawValue, flags:[.create], tx:newTrans)
			do {
				self.pubkey_following = try env.openDatabase(named:Databases.user_following.rawValue, flags:[.create, .dupSort], tx:newTrans)
			} catch LMDBError.incompatible {
				let getDB = try env.openDatabase(named:Databases.user_following.rawValue, flags:[.create, .dupSort], tx:newTrans)
				try getDB.deleteDatabase(tx:newTrans)
				self.pubkey_following = try env.openDatabase(named:Databases.user_following.rawValue, flags:[.create, .dupSort], tx:newTrans)
			}
			
			self.pubkey = publicKey
			self.env = env
			self.logger = Logger(label: "follows-engine.mdb")
			try newTrans.commit()
			
		}

		func set(pubkey:nostr.Key, follows:Set<nostr.Key>, tx someTrans:QuickLMDB.Transaction) throws {
			let nowDate = DBUX.Date()
			// open cursors
			let dateCursor = try pubkey_date.cursor(tx:someTrans)
			let cursor = try pubkey_following.cursor(tx:someTrans)
			do {
				_ = try cursor.getEntry(.set, key:pubkey)
				try cursor.deleteEntry(flags:[.noDupData])
			} catch LMDBError.notFound {}
			let follows = follows.sorted(by: { $0 < $1 })
			for curFollow in follows {
				try cursor.setEntry(value:curFollow, forKey:pubkey)
			}
			try dateCursor.setEntry(value:nowDate, forKey:pubkey)
		}

		func getFollows(pubkey:nostr.Key, tx someTrans:QuickLMDB.Transaction) throws -> Set<nostr.Key> {
			let followsCursor = try pubkey_following.cursor(tx:someTrans)
			var buildVal = Set<nostr.Key>()
			do {
				for (_, curFollow) in try followsCursor.makeDupIterator(key: pubkey) {
					buildVal.update(with:nostr.Key(curFollow)!)
				}
			} catch LMDBError.notFound {}
			return buildVal
		}


		func getFriends(_ pubkeys:Set<nostr.Key>, tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Key:Set<nostr.Key>] {
			let followsCursor = try pubkey_following.cursor(tx:someTrans)
			var buildRet = [nostr.Key:Set<nostr.Key>]()
			for curPubkey in pubkeys {
				var buildVal = Set<nostr.Key>()
				defer {
					buildRet[curPubkey] = buildVal
				}
				let dupIterator = try followsCursor.makeDupIterator(key:curPubkey)
				for (_, curFollow) in followsCursor {
					buildVal.update(with:nostr.Key(curFollow)!)
				}
			}
			return buildRet
		}

		func isFriend(pubkey:nostr.Key, with somePossibleFriend:nostr.Key, tx someTrans:QuickLMDB.Transaction) throws -> Bool {
			let followsCursor = try self.pubkey_following.cursor(tx:someTrans)
			do {
				let _ = try followsCursor.getEntry(.getBoth, key:pubkey, value:somePossibleFriend)
				return true
			} catch LMDBError.notFound {
				return false
			}
		}
	}
}

extension DBUX.FollowsEngine {
	// returns a boolean indicating whether or not the given pubkey is a friend of the current user
	func isFriend(pubkey:nostr.Key) throws -> Bool {
		return try self.env.transact(readOnly:true) { newTrans in
			return try self.isFriend(pubkey:self.pubkey, with:pubkey, tx:newTrans)
		}
	}

	// returns a boolean indicating whether or not the given pubkey is a friend of a friend of the current user
	func isFriendOfFriend(pubkey:nostr.Key) throws -> Bool {
		return try self.env.transact(readOnly:true) { newTrans in
			let myFriends = try self.getFollows(pubkey:self.pubkey, tx:newTrans)
			let allFriendFollows = try self.getFriends(myFriends, tx:newTrans)
			var allUIDs = Set<nostr.Key>()
			for (_, curFollows) in allFriendFollows {
				allUIDs.formUnion(curFollows)
			}
			return allUIDs.contains(pubkey)
		}
	}

	func isInFriendosphere(pubkey:nostr.Key) throws -> Bool {
		try self.env.transact(readOnly:true) { followTrans in
			let isf = try self.isFriend(pubkey:self.pubkey, with:pubkey, tx:followTrans)
			let myFriends = try self.getFollows(pubkey:self.pubkey, tx:followTrans)
			let allFriendFollows = try self.getFriends(myFriends, tx:followTrans)
			var allUIDs = Set<nostr.Key>()
			for (_, curFollows) in allFriendFollows {
				allUIDs.formUnion(curFollows)
			}
			let isFOF = allUIDs.contains(pubkey)
			try followTrans.commit()
			return isf || isFOF
		}
	}
}

extension DBUX {
	// mute related - allows a local user to mute a given event or user
	struct ModerationDB {
		static let name = "moderation-engine.mdb"
		static let deltaSize = size_t(5.12e+8)
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger
		
		enum Databases:String {
			case mutelist = "event-mutes"
			case user_mutelist = "user-mutes"
		}

		let eventMutes:Database		/// [nostr.Event.UID:DBUX.Date?] (key is the event ID, value is date that it will be muted until (- for indefinite)
		let userMutes:Database		///	[nostr.Key:DBUX.Date?] (key is the user public key, value is date that it will be muted until (- for indefinite)
		
		init(base:URL, env:QuickLMDB.Environment, pubkey:nostr.Key) throws {
			self.env = env
			self.base = base
			self.pubkey = pubkey
			self.logger = Logger(label: "moderation-engine.mdb")
			let newTrans = try Transaction(self.env, readOnly:false)
			self.eventMutes = try env.openDatabase(named:Databases.mutelist.rawValue, flags:[.create], tx:newTrans)
			self.userMutes = try env.openDatabase(named:Databases.user_mutelist.rawValue, flags:[.create], tx:newTrans)
			
			try newTrans.commit()
		}
		
		/// mute a given set of events until a given date
		/// - Parameter events: a dictionary of events to mute, with the date that they should be muted until
		///  - if the date is nil, the event will be muted indefinitely
		func mute(events:[nostr.Event:DBUX.Date?], tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try Transaction(self.env, readOnly:false, parent:someTrans)
			let eventCursor = try self.eventMutes.cursor(tx:subTrans)
			for (curEvent, curDate) in events {
				if let hasDate = curDate {
					try eventCursor.setEntry(value:hasDate, forKey:curEvent.id)
				} else {
					try eventCursor.setEntry(value:"-", forKey:curEvent.id)
				}
			}
			try subTrans.commit()
		}

		/// mute a given set of users until a given date
		/// - Parameter users: a dictionary of users to mute, with the date that they should be muted until
		///  - if the date is nil, the user will be muted indefinitely
		func mute(users:[nostr.Key:DBUX.Date?], tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try Transaction(self.env, readOnly:false, parent:someTrans)
			let userCursor = try self.userMutes.cursor(tx:subTrans)
			for (curUser, curDate) in users {
				if let hasDate = curDate {
					try userCursor.setEntry(value:hasDate, forKey:curUser)
				} else {
					try userCursor.setEntry(value:"-", forKey:curUser)
				}
			}
			try subTrans.commit()
		}
	}
}
