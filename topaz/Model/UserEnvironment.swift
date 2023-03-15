//
//  UserEnvironment.swift
//  topaz
//
//  Created by Tanner Silva on 3/6/23.
//

import Foundation
import SwiftUI
import QuickLMDB
import Logging
import SwiftBlake2

// FRIENDS:
// a user may be considered a friend to the current user if the current user is following them
extension UE {
	class Profiles:ObservableObject {
		enum Databases:String {
			case profile_main = "_profiles-core"
		}

		let env:QuickLMDB.Environment
		fileprivate let decoder = JSONDecoder()
		
		let profilesDB:Database  // [String:Pofile] where the key is the pubkey

		init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			self.env = env
			self.profilesDB = try env.openDatabase(named:Databases.profile_main.rawValue, flags:[.create], tx:subTrans)
			try subTrans.commit()
		}

		/// gets a profile from the database
		func getPublicKeys(publicKeys:Set<String>) throws -> [String:nostr.Profile] {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:true)
			let getCursor = try self.profilesDB.cursor(tx:newTrans)
			var profiles = [String:nostr.Profile]()
			for curID in publicKeys {
				let getProfile = Data(try getCursor.getEntry(.set, key:curID).value)!
				let decoded = try self.decoder.decode(nostr.Profile.self, from:getProfile)
				profiles[curID] = decoded
			}
			try newTrans.commit()
			return profiles
		}

		/// set a profile in the database
		func setPublicKeys(_ profiles:[String:nostr.Profile]) throws {
			let newTrans = try QuickLMDB.Transaction(self.env, readOnly:false)
			let encoder = JSONEncoder()
			let profileCursor = try self.profilesDB.cursor(tx:newTrans)
			for (pubkey, curProfile) in profiles {
				let encoded = try encoder.encode(curProfile)
				try profileCursor.setEntry(value:encoded, forKey:pubkey)
			}
			try newTrans.commit()
		}
	}
}

class UE:ObservableObject {

	// the databases 
	enum Databases:String {
		case userContext = "-usercontext"
		case userSettings = "-usersettings"
		case userInfo = "-userinfo"
		case events_core = "-events-core"
		case profile_core = "-profile-core"
	}
	
	// for data serialization
	let encoder = JSONEncoder()
	let decoder = JSONDecoder()

	/// primary data for this UE instance
	let logger:Logger
	let env:QuickLMDB.Environment
	let uuid:String
	let keypair:KeyPair

	enum UserContext:String, MDB_convertible {
		case badgeStatus = "badge_status" // ViewBadgeStatus
	}
	let userContext:Database


	enum UserInfo:String, MDB_convertible {
		case relays = "user_relays" // [Relay]: where index 0 is the primary relay
		case pubkey = "user_pub"	// String: the public key for this current user
		case privkey = "user_pk"	// String?: the private key for this current user
	}
	let userInfo:Database

	/// user settings
	enum Settings:String, MDB_convertible {
		///idek what goes here yet
		case viewMode = "viewMode"	// ViewMode
	}
	let userSettings:Database

	// event info
	let eventsDB:UE.EventsDB

	// contacts db
	let contactsDB:UE.Contacts

	/// stores the primary root view that the user is currently viewing
	enum ViewMode:Int, MDB_convertible {
		case home
		case notifications
		case dms
		case search
		case profile
	}
	
	// stores the primary tab viwe badge status for the user
	struct ViewBadgeStatus:Codable {
		var homeBadge:Bool
		var notificationsBadge:Bool
		var dmsBadge:Bool
		var searchBadge:Bool
		var profileBadge:Bool
	}
	@Published var badgeStatus:ViewBadgeStatus {
		didSet {
			do {
				let jsonData = try encoder.encode(badgeStatus)
				try self.userContext.setEntry(value:jsonData, forKey:UserContext.badgeStatus.rawValue, tx:nil)
				self.logger.info("badge status modified.", metadata:["new_value": "\(badgeStatus)"])
			} catch let error {
				self.logger.error("failed to update badge status in database.", metadata:["error": "\(error)"])
			}
		}
	}
	
	@Published var viewMode:ViewMode {
		didSet {
			do {
				try self.userSettings.setEntry(value:viewMode, forKey:Settings.viewMode.rawValue, tx:nil)
				self.logger.info("view mode modified.", metadata:["new_value": "\(viewMode)"])
			} catch let error {
				self.logger.error("failed to update view mode in database.", metadata:["error": "\(error)"])
			}
		}
	}
	let profilesDB:Profiles

	init(keypair:KeyPair, uuid:String = UUID().uuidString) throws {
		let makeLogger = Topaz.makeDefaultLogger(label:"user-environment")
		self.logger = makeLogger
		let makeEnv = Topaz.openLMDBEnv(named:"topaz-u-\(keypair.pubkey.prefix(8))")
		switch makeEnv {
		case let .success(env):
			let newTrans = try QuickLMDB.Transaction(env, readOnly:false)
			let makeSettings = try env.openDatabase(named:Databases.userSettings.rawValue, flags:[.create], tx:newTrans)
			self.userSettings = makeSettings
			let makeUserInfo = try env.openDatabase(named:Databases.userInfo.rawValue, flags:[.create], tx:newTrans)
			self.userInfo = makeUserInfo
			let uc = try env.openDatabase(named:Databases.userContext.rawValue, flags:[.create], tx:newTrans)
			self.userContext = uc
			// public key always present
			try makeUserInfo.setEntry(value:keypair.pubkey, forKey:UserInfo.pubkey.rawValue, tx:newTrans)
			try makeUserInfo.setEntry(value:keypair.privkey, forKey:UserInfo.privkey.rawValue, tx:newTrans)
			
			// initialize the view mode
			do {
				let getViewMode = try self.userSettings.getEntry(type:ViewMode.self, forKey:Settings.viewMode.rawValue, tx:newTrans)!
				_viewMode = Published(wrappedValue:getViewMode)
			} catch LMDBError.notFound {
				// this is the first launch, place a default value
				try self.userSettings.setEntry(value:ViewMode.home, forKey:Settings.viewMode.rawValue, tx:newTrans)
				_viewMode = Published(wrappedValue:.home)
			}

			// initialize the connected relays
			var buildRelays = [Relay:RelayConnection]()
			self.uuid = uuid
			self.env = env
			
			// build the relays (this must be done after self is initialized so relayconnections can reference self)
			let allRelays:[Relay]
			do {
				allRelays = try makeUserInfo.getEntry(type:[Relay].self, forKey:UserInfo.relays.rawValue, tx:newTrans)!
			} catch LMDBError.notFound {
				allRelays = Topaz.bootstrap_relays
				try makeUserInfo.setEntry(value:Topaz.bootstrap_relays, forKey:UserInfo.relays.rawValue, tx:newTrans)
			}

			// build the view badge status
			do {
				let getBadgeStatus = try JSONDecoder().decode(ViewBadgeStatus.self, from: try uc.getEntry(type:Data.self, forKey:UserContext.badgeStatus.rawValue, tx:newTrans)!)
				_badgeStatus = Published(wrappedValue:getBadgeStatus)
			} catch LMDBError.notFound {
				// this is the first launch, place a default value
				let defaultBadgeStatus = ViewBadgeStatus(homeBadge:false, notificationsBadge:false, dmsBadge:true, searchBadge:false, profileBadge:false)
				try uc.setEntry(value:try JSONEncoder().encode(defaultBadgeStatus), forKey:UserContext.badgeStatus.rawValue, tx:newTrans)
				_badgeStatus = Published(wrappedValue:defaultBadgeStatus)
			}

			// initialize the events database
			let makeEventsDB = try UE.EventsDB(env:env, tx:newTrans)
			self.eventsDB = makeEventsDB

			// initialize the contacts database
			let makeContactsDB = try UE.Contacts(publicKey:keypair.pubkey, env:env, tx:newTrans)
			self.contactsDB = makeContactsDB
			
			// initialize the profiles database
			let makeProfilesDB = try Profiles(env, tx:newTrans)
			self.profilesDB = makeProfilesDB
			self.keypair = keypair
			
			
			try newTrans.commit()
			self.logger.info("instance initialized.", metadata:["public_key":"\(keypair.pubkey)"])
		case let .failure(err):
			throw err
		}
	}

	/// opens a new transaction for the user environment
	func transact(readOnly:Bool) throws -> QuickLMDB.Transaction {
		return try QuickLMDB.Transaction(self.env, readOnly:readOnly)
	}
}

extension UE:Hashable {
	func hash(into hasher: inout Hasher) {
		hasher.combine(keypair.pubkey)
	}
}

extension UE:Equatable {
	static func == (lhs: UE, rhs: UE) -> Bool {
		return lhs.uuid == rhs.uuid && lhs.keypair.pubkey == rhs.keypair.pubkey
	}
}

	

extension UE {
	// the primary contacts database that assures that a user is able to reach any given public key on the network.
	class Contacts:ObservableObject {
		enum Databases:String {
			case following_asof = "-following-asof"
			case user_relays = "my_relays" // Set<Relay>
		}
		
		let publicKey:String
		let env:QuickLMDB.Environment

		let followDB:FollowsDB

		init(publicKey:String, env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			self.publicKey = publicKey
			self.env = env
			self.followDB = try FollowsDB(env, tx:someTrans)
		}
		// mute related - allows a local user to mute a given event or user
		struct ModerationDB {
			enum Databases:String {
				case mutelist = "event_mutelist"
				case user_mutelist = "user_mutelist"
			}
			
			let env:QuickLMDB.Environment
			
			let eventMutes:Database		/// [String:Date?] (key is the event ID, value is date that it will be muted until (- for indefinite)
			let userMutes:Database		///	[String:Date?] (key is the user public key, value is date that it will be muted until (- for indefinite)
			
			init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
				self.env = env
				self.eventMutes = try env.openDatabase(named:Databases.mutelist.rawValue, flags:[.create], tx:someTrans)
				self.userMutes = try env.openDatabase(named:Databases.user_mutelist.rawValue, flags:[.create], tx:someTrans)
			}
			
			/// mute a given set of events until a given date
			/// - Parameter events: a dictionary of events to mute, with the date that they should be muted until
			///  - if the date is nil, the event will be muted indefinitely
			func mute(events:[nostr.Event:Date?], tx someTrans:QuickLMDB.Transaction? = nil) throws {
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
			func mute(users:[String:Date?], tx someTrans:QuickLMDB.Transaction? = nil) throws {
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

		// following related
		/// this database stores the list of users that the user is following
		struct FollowsDB {
			enum Databases:String {
				case pubkey_refreshDate = "pubkey_refreshDate"
				case user_following = "pubkey_follows"
				case follower_user = "follower_follows"
			}

			let pubkey_date:Database			// stores the last time that the user profile information was updated.			[String:Date]
			let pubkey_following:Database		// stores the list of pubkeys that the user is following						[String:String?] * DUP * (value will be \0 if an account follows nobody)
				
			init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
				self.pubkey_date = try env.openDatabase(named:Databases.pubkey_refreshDate.rawValue, flags:[.create], tx:someTrans)
				self.pubkey_following = try env.openDatabase(named:Databases.user_following.rawValue, flags:[.create, .dupSort], tx:someTrans)
			}

			func set(pubkey:String, follows:Set<String>, tx someTrans:QuickLMDB.Transaction) throws {
				let nowDate = Date()
				// open cursors
				let dateCursor = try pubkey_date.cursor(tx:someTrans)
				let cursor = try pubkey_following.cursor(tx:someTrans)
				var needsAdding = follows
				let dupIterator:QuickLMDB.Cursor.CursorDupIterator
				do {
					dupIterator = try cursor.makeDupIterator(key:pubkey)
				} catch LMDBError.notFound {
					// there are no entries for this user, so we can just add them all
					for curAdd in needsAdding {
						try dateCursor.setEntry(value:nowDate, forKey:pubkey)
						try cursor.setEntry(value:curAdd, forKey:pubkey)
						// try invertCursor.setEntry(value:pubkey, forKey:curAdd)
					}
					return
				}
				// check the status of all the current follow entries in the database
				for (_, curFollow) in dupIterator {
					let curFollowStr = String(curFollow)!
					if needsAdding.contains(curFollowStr) {
						// the entry is already in the database, so we don't need to add it
						needsAdding.remove(curFollowStr)
					} else {
						// the entry is in the database, but it is no longer present in the latest followers list, so we need to remove it
						try dateCursor.getEntry(.set, key:pubkey)
						try dateCursor.deleteEntry()
						try cursor.getEntry(.set, key:pubkey)
						try cursor.deleteEntry()
					}
				}
				// add any outstanding entries that did not get resolved in the previous loop
				for curAdd in needsAdding {
					try dateCursor.setEntry(value:nowDate, forKey:pubkey)
					try cursor.setEntry(value:curAdd, forKey:pubkey)
				}
			}

			func getFollows(pubkey:String, tx someTrans:QuickLMDB.Transaction) throws -> Set<String> {
				let followsCursor = try pubkey_following.cursor(tx:someTrans)
				var buildVal = Set<String>()
				for (_, curFollow) in followsCursor {
					buildVal.update(with:String(curFollow)!)
				}
				return buildVal
			}


			func getFriends(_ pubkeys:Set<String>, tx someTrans:QuickLMDB.Transaction) throws -> [String:Set<String>] {
				let followsCursor = try pubkey_following.cursor(tx:someTrans)
				var buildRet = [String:Set<String>]()
				for curPubkey in pubkeys {
					var buildVal = Set<String>()
					defer {
						buildRet[curPubkey] = buildVal
					}
					let dupIterator = try followsCursor.makeDupIterator(key:curPubkey)
					for (_, curFollow) in followsCursor {
						buildVal.update(with:String(curFollow)!)
					}
				}
				return buildRet
			}

			func isFriend(pubkey:String, with somePossibleFriend:String, tx someTrans:QuickLMDB.Transaction) throws -> Bool {
				let followsCursor = try self.pubkey_following.cursor(tx:someTrans)
				do {
					let _ = try followsCursor.getEntry(.getBoth, key:pubkey, value:somePossibleFriend)
					return true
				} catch LMDBError.notFound {
					return false
				}
			}
		}

		// returns a boolean indicating whether or not the given pubkey is a friend of the current user
		func isFriend(pubkey:String, tx someTrans:QuickLMDB.Transaction) throws -> Bool {
			return try self.followDB.isFriend(pubkey:self.publicKey, with:pubkey, tx:someTrans)
		}

		// returns a boolean indicating whether or not the given pubkey is a friend of a friend of the current user
		func isFriendOfFriend(pubkey:String, tx someTrans:QuickLMDB.Transaction) throws -> Bool {
			let myFriends = try self.followDB.getFollows(pubkey:self.publicKey, tx:someTrans)
			let allFriendFollows = try self.followDB.getFriends(myFriends, tx:someTrans)
			var allUIDs = Set<String>()
			for (_, curFollows) in allFriendFollows {
				allUIDs.formUnion(curFollows)
			}
			return allUIDs.contains(pubkey)
		}

		func isInFriendosphere(pubkey:String, tx someTrans:QuickLMDB.Transaction) throws -> Bool {
			let isf = try self.isFriend(pubkey:pubkey, tx:someTrans)
			let isFOF = try self.isFriendOfFriend(pubkey:pubkey, tx:someTrans)
			return isf || isFOF
		}

		// relay related
		/// this database stores the list of relays that the user has listed in their profile
		struct RelaysDB {
			static func produceRelayHash<B>(url:B) throws -> Data where B:ContiguousBytes {
				var newHasher = try Blake2bHasher(outputLength:16)
				try newHasher.update(url)
				return try newHasher.export()
			}
			let pubkey_relayHash:Database		// stores the list of relay hashes that the user has listed in their profile	[String:String] * DUP *
			let relayHash_relayString:Database	// stores the full relay URL for a given relay hash								[String:String]
			let relayHash_pubKey:Database		// stores the public key for a given relay hash									[String:String] * DUP *
		}
	}
}

extension UE {
	class EventsDB:ObservableObject {
		struct KindDatabase {
			static let logger:Logger = Logger(label:"com.nostr.eventsdb")

			enum Databases:String, MDB_convertible {
				case uid_kind = "uid-kind"
				case kind_uid = "kind-uid"
			}

			let env:QuickLMDB.Environment

			// * does not allow an override of an existing entry if the values are not the same *
			let uid_kind:Database		// [UID:String]
			let kind_uid:Database		// [Kind:String] * DUP *

			init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction? = nil) throws {
				self.env = env
				let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
				self.uid_kind = try env.openDatabase(named:Databases.uid_kind.rawValue, flags:[.create], tx:subTrans)
				self.kind_uid = try env.openDatabase(named:Databases.kind_uid.rawValue, flags:[.create], tx:subTrans)
				try subTrans.commit()
			}

			/// bulk import events into the database
			/// - for each public key, the event kinds will attempt to be assigned
			/// - will NOT overwrite existing data if the specified public key is already in the database
			/// - will NOT throw ``LMDBError.keyExists`` if the public key is already in the database with the same kind
			func setEvent(_ events:[nostr.Event], tx someTrans:QuickLMDB.Transaction? = nil) throws {
				let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				let kUIDCursor = try self.kind_uid.cursor(tx:subTrans)
				for event in events {
					do {
						try uidKCursor.setEntry(value:event.kind, forKey:event.uid, flags:[.noOverwrite])
					} catch {
						// throw an error if the key already exists and the value is not the same
						guard nostr.Event.Kind(rawValue:Int(try uidKCursor.getEntry(.set, key:event.uid).value)!) == event.kind else {
							throw LMDBError.keyExists
						}
					}
					try kUIDCursor.setEntry(value:event.uid, forKey:event.kind)
				}
				try subTrans.commit()
				Self.logger.debug("successfully installed events.", metadata:["count": "\(events.count)"])
			}

			/// get all kinds for a given uid
			/// - never throws LMDBError.notFound
			func getKinds(uids:Set<String>, tx someTrans:QuickLMDB.Transaction? = nil) throws -> [String:nostr.Event.Kind] {
				let subTrans = try Transaction(env, readOnly:true, parent: someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				var ret = [String:nostr.Event.Kind]()
				for uid in uids {
					ret[uid] = nostr.Event.Kind(rawValue:Int(try uidKCursor.getEntry(.set, key:uid).value)!)
				}
				try subTrans.commit()
				return ret
			}

			/// removes the given uids from the database
			func deleteEvents(uids:Set<String>, tx someTrans:QuickLMDB.Transaction? = nil) throws {
				let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
				let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
				let kindUIDCursor = try self.kind_uid.cursor(tx:subTrans)
				for curID in uids {
					let getKind = try uidKCursor.getEntry(.set, key:curID).value
					let asKind = nostr.Event.Kind(getKind)!
					try kindUIDCursor.getEntry(.getBoth, key:asKind, value:curID)
					try kindUIDCursor.deleteEntry()
					try uidKCursor.deleteEntry()
				}
				try subTrans.commit()
				Self.logger.debug("successfully deleted events.", metadata:["count": "\(uids.count)"])
			}
		}

		fileprivate let encoder = JSONEncoder()


		let env:QuickLMDB.Environment
		
		// stores a given event ID and the JSON-encoded event.
		let eventDB_core:Database 	// [String:nostr.Event]

		init(env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			self.env = env
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			self.eventDB_core = try env.openDatabase(named:Databases.events_core.rawValue, flags:[.create], tx:subTrans)
			try subTrans.commit()
		}

		func writeEvents(_ events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			let eventCursor = try self.eventDB_core.cursor(tx:subTrans)
			for curEvent in events {
				let encodedData = try encoder.encode(curEvent)
				try eventCursor.setEntry(value:encodedData, forKey:curEvent.uid)
			}
			try subTrans.commit()
		}

		func getEvents(tx someTrans:QuickLMDB.Transaction? = nil) -> Result<[nostr.Event], Swift.Error> {
			do {
				let subTrans = try Transaction(env, readOnly:true, parent:someTrans)
				let cursor = try self.eventDB_core.cursor(tx:subTrans)
				var buildEvents = [nostr.Event]()
				for (_, curEvent) in cursor {
					buildEvents.append(try JSONDecoder().decode(nostr.Event.self, from:Data(curEvent)!))
				}
				try subTrans.commit()
				return .success(buildEvents)
			} catch let error {
				return .failure(error)
			}
		}
	}
}


extension UE {
	class ZapsDB:ObservableObject {
		static let logger = Topaz.makeDefaultLogger(label:"zaps-db")
		enum Databases:String {
			case zap_core = "zap_core"
			case zap_totals = "zap_totals"
			case my_zaps = "my_zaps"
		}
		fileprivate let pubkey:String
		let env:QuickLMDB.Environment
		
		let zap_core:Database	// [String:Zap] where key is the zaps event id and value is the zap codable data itself
		let zap_totals:Database	// [String:UInt64] where key is the zaps target id and value is the total amount of zap value for that event
		let my_zaps:Database	// [String:String] * DUP * where key is the note target note ID, value is the zaps event ID
		
		init(pubkey:String, env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			self.pubkey = pubkey
			self.env = env
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			self.zap_core = try env.openDatabase(named:Databases.zap_core.rawValue, flags:[.create], tx:subTrans)
			self.zap_totals = try env.openDatabase(named:Databases.zap_totals.rawValue, flags:[.create], tx:subTrans)
			self.my_zaps = try env.openDatabase(named:Databases.my_zaps.rawValue, flags:[.create, .dupSort], tx:subTrans)
			try subTrans.commit()
			Self.logger.info("instance successfully initialized.")
		}

		/// adds a series of zaps into the databsae
		/// - the zap is json encoded and stored against its event ID
		/// - the zap total is stored against the target ID
		/// if this is a zap that originated from the public key of this UE, then the zap is also stored against the note ID of the target note
		func add(zaps:[Zap], tx someTrans:QuickLMDB.Transaction? = nil) throws {
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			let zapCursor = try self.zap_core.cursor(tx:subTrans)
			let totalsCursor = try self.zap_totals.cursor(tx:subTrans)
			let myZapCursor = try self.my_zaps.cursor(tx:subTrans)
			let encoder = JSONEncoder()
			for curZap in zaps {
				// no payments to self.
				guard curZap.request.ev.pubkey != curZap.target.pubkey else {
					continue
				}
				// document the zap itself
				do {
					try zapCursor.setEntry(value:try encoder.encode(curZap), forKey:curZap.event.uid, flags:[.noOverwrite])
				} catch let error {
					// cannot add this zap because it already exists
					Self.logger.error("the zaps db already contains a zap with the event id \(curZap.event.uid).", metadata:["error": "\(error)"])
					throw error
				}
				do {
					let existingValue = UInt64(try totalsCursor.getEntry(.set, key:curZap.event.uid).value)!
					try totalsCursor.setEntry(value:existingValue + UInt64(curZap.invoice.amount), forKey:curZap.event.uid)
				} catch LMDBError.notFound {
					try totalsCursor.setEntry(value:curZap.invoice.amount, forKey:curZap.event.id)
				}
				// record our zaps for an event
				if curZap.request.ev.pubkey == pubkey {
					switch curZap.target {
						case .note(let note_target):
						try myZapCursor.setEntry(value:curZap.event.uid, forKey:note_target.note_id)
						case .profile(_):
							break;
					}
				}
			}
			Self.logger.debug("successfully added zaps.", metadata:["count": "\(zaps.count)"])
			try subTrans.commit()
		}

		func get(eventIDs:Set<String>, tx someTrans:QuickLMDB.Transaction? = nil) throws -> [String:Zap] {
			let decoder = JSONDecoder()
			let subTrans = try Transaction(env, readOnly:true, parent:someTrans)
			let zapCursor = try self.zap_core.cursor(tx:subTrans)
			var buildZaps = [String:Zap]()
			for curID in eventIDs {
				do {
					let zapData = Data(try zapCursor.getEntry(.set, key:curID).value)!
					let asZap = try decoder.decode(Zap.self, from:zapData)
					buildZaps[curID] = asZap
				} catch LMDBError.notFound {
					Self.logger.error("could not find zap for event id \(curID).")
					throw LMDBError.notFound
				}
			}
			return buildZaps
		}
	}
}
