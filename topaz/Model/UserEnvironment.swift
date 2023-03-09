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

class UE:ObservableObject {
	enum Databases:String {
		case userSettings = "-usersettings"
		case userInfo = "-userinfo"
	}

	/// primary data for this UE instance
	let logger:Logger
	let env:QuickLMDB.Environment
	let publicKey:String
	let uuid:String

	enum UserInfo:String, MDB_convertible {
		case relays = "user_relays" // [Relay] where index 0 is the primary relay
	}
	let userInfo:Database

	/// user settings
	enum Settings:String, MDB_convertible {
		///idek what goes here yet
		case viewMode = "viewMode"	// ViewMode
	}
	let userSettings:Database
	
	/// stores the primary root view that the user is currently viewing
	enum ViewMode:UInt8, MDB_convertible {
		case timeline = 0
		case devView = 1
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

	/// this is the pool of connected relays that the user has
	@State var connectedRelays:[Relay:RelayConnection]

	init(publicKey:String, uuid:String = UUID().uuidString) throws {
		let makeLogger = Topaz.makeDefaultLogger(label:"user-environment")
		self.logger = makeLogger
		let makeEnv = Topaz.openLMDBEnv(named:"topaz-u-\(publicKey)")
		switch makeEnv {
		case let .success(env):
			let newTrans = try QuickLMDB.Transaction(env, readOnly:false)
			let makeSettings = try env.openDatabase(named:Databases.userSettings.rawValue, flags:[.create], tx:newTrans)
			self.userSettings = makeSettings
			let makeUserInfo = try env.openDatabase(named:Databases.userInfo.rawValue, flags:[.create], tx:newTrans)
			self.userInfo = makeUserInfo
			// initialize the view mode
			do {
				let getViewMode = try self.userSettings.getEntry(type:ViewMode.self, forKey:Settings.viewMode.rawValue, tx:newTrans)!
				_viewMode = Published(wrappedValue:getViewMode)
			} catch LMDBError.notFound {
				// this is the first launch, place a default value
				try self.userSettings.setEntry(value:ViewMode.timeline, forKey:Settings.viewMode.rawValue, tx:newTrans)
				_viewMode = Published(wrappedValue:.timeline)
			}

			// initialize the connected relays
			var buildRelays = [Relay:RelayConnection]()
			self.connectedRelays = buildRelays
			self.publicKey = publicKey
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
			for relay in allRelays {
				buildRelays[relay] = RelayConnection(url:relay.url) { [weak self, log = logger] someEvent in
					log.info("relay connection info found.", metadata: ["info":"\(someEvent)"])
					guard let self = self else { return }
					return
				}
			}
			try newTrans.commit()
			self.logger.info("instance initialized.", metadata:["public_key":"\(publicKey)"])
		case let .failure(err):
			throw err
		}
	}
}

extension UE:Hashable {
	func hash(into hasher: inout Hasher) {
		hasher.combine(uuid)
		hasher.combine(publicKey)
	}
}

extension UE:Equatable {
	static func == (lhs: UE, rhs: UE) -> Bool {
		return lhs.uuid == rhs.uuid && lhs.publicKey == rhs.publicKey
	}
}

	

extension UE {
	// the primary contacts database that assures that a user is able to reach any given public key on the network.
	class Contacts:ObservableObject {
		enum Databases:String {
			case following_asof = "-following-asof"
			case user_relays = "my_relays" // Set<Relay>
		}

//		let publicKey:String
//		let env:QuickLMDB.Environment

		// databases that are used to store following information
//		let pubkey_asof:Database			// stores the last time that the user profile information was updated.		[String:Date]
		
		// following related
		/// this database stores the list of users that the user is following
		struct FollowsDB {
			enum Databases:String {
				case pubkey_refreshDate = "pubkey_refreshDate"
				case user_following = "pubkey_follows"
				case follower_user = "follower_follows"
			}
			let pubkey_date:Database			// stores the last time that the user profile information was updated.			[String:Date]
			let pubkey_following:Database		// stores the list of pubkeys that the user is following						[String:String?] * DUP * (value will be 0 length if an account follows nobody)
			let _follower_following:Database	// stores a list of pubkeys that are following the user							[String:String] * DUP * (technically optional if an account has no followers)
			init(_ env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
				self.pubkey_date = try env.openDatabase(named:Databases.pubkey_refreshDate.rawValue, flags:[.create], tx:someTrans)
				self.pubkey_following = try env.openDatabase(named:Databases.user_following.rawValue, flags:[.create], tx:someTrans)
				self._follower_following = try env.openDatabase(named:Databases.follower_user.rawValue, flags:[.create], tx:someTrans)
			}
			func set(pubkey:String, follows:Set<String>, tx someTrans:QuickLMDB.Transaction) throws {
				let cursor = try pubkey_following.cursor(tx:someTrans)
				let invertCursor = try _follower_following.cursor(tx:someTrans)
				var deletes:UInt = 0
				var adds:UInt = 0
				var needsAdding = follows
				let dupIterator:QuickLMDB.Cursor.CursorDupIterator
				do {
					dupIterator = try cursor.makeDupIterator(key:pubkey)
				} catch let error {
					// there are no entries for this user, so we can just add them all
					for curAdd in needsAdding {
						try cursor.setEntry(value:curAdd, forKey:pubkey)
						try cursor.setEntry(value:pubkey, forKey:curAdd)
						adds += 1
					}
					return
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

		struct TagDatabase {

			let primaryKind:nostr.Event.Tag.Kind
		}
		let env:QuickLMDB.Environment

		init(pubKey:String, env:QuickLMDB.Environment, tx someTrans:QuickLMDB.Transaction) throws {
			self.env = env
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			try subTrans.commit()
		}

	}
}
