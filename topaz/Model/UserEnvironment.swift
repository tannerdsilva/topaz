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
import AsyncAlgorithms

class UE:ObservableObject {
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

	enum UserInfo:String, MDB_convertible {
		case relays = "user_relays" // [Relay]: where index 0 is the primary relay
		case pubkey = "user_pub"	// String: the public key for this current user
		case privkey = "user_pk"	// String?: the private key for this current user
	}
	let userInfo:Database
	let userSettings:Database

	// event info
	let eventsDB:UE.EventsDB

	// contacts db
	let contactsDB:UE.Contacts

	// profiles db
	let profilesDB:Profiles
	
	// context
	var contextDB:UE.Context

	// relays
	let relaysDB:UE.RelaysDB

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

			// public key always present
			try makeUserInfo.setEntry(value:keypair.pubkey, forKey:UserInfo.pubkey.rawValue, tx:newTrans)
			try makeUserInfo.setEntry(value:keypair.privkey, forKey:UserInfo.privkey.rawValue, tx:newTrans)

			self.uuid = uuid
			self.env = env

			// initialize the events database
			let makeEventsDB = try UE.EventsDB(env:env, tx:newTrans)
			self.eventsDB = makeEventsDB

			// initialize the contacts database
			let makeContactsDB = try UE.Contacts(publicKey:keypair.pubkey, env:env, tx:newTrans)
			self.contactsDB = makeContactsDB
			
			let makeContextDB = try UE.Context(env, tx:newTrans)
			self.contextDB = makeContextDB
			
			// initialize the profiles database
			let makeProfilesDB = try Profiles(pubkey:keypair.pubkey, env, tx:newTrans)

			// initialize the relays database
			let base = try FileManager.default.url(for:.libraryDirectory, in: .userDomainMask, appropriateFor:nil, create:true)
			let makeRelaysDB = try UE.RelaysDB(base:base, pubkey:keypair.pubkey)
			let myRelays = try makeRelaysDB.getRelays(pubkey:keypair.pubkey)
			
			self.relaysDB = makeRelaysDB

			self.profilesDB = makeProfilesDB
			self.keypair = keypair
			
			let homeSubs = try self.buildMainUserFilters(tx:newTrans)
			for curRelay in myRelays {
				try makeRelaysDB.add(subscriptions:[nostr.Subscribe(sub_id:UUID().uuidString, filters:homeSubs)], to:curRelay)
			}
			Task.detached { [weak self, hol = makeRelaysDB.holder] in
				guard let self = self else {
					return
				}
				let decoder = JSONDecoder()
				for try await curEvs in hol {
					self.logger.notice("flushing event holder.")
					defer {
						self.logger.info("done.")
					}
					let newTrans = try Transaction(self.env, readOnly:false)
					var buildProfiles = [String:nostr.Profile]()
					for curEv in curEvs {
						switch curEv.kind {
						case .metadata:
							do {
								let asData = Data(curEv.content.utf8)
								let decoded = try decoder.decode(nostr.Profile.self, from:asData)
								self.logger.info("successfully decoded profile", metadata:["pubkey":"\(curEv.pubkey)"])
								buildProfiles[curEv.pubkey] = decoded
							} catch {
								self.logger.error("failed to decode profile.")
							}
						case .contacts:
							do {
								let asData = Data(curEv.content.utf8)
								let relays = Set(try decoder.decode([String:[String:Bool]].self, from:asData).keys)
								var following = Set<String>()
								for curTag in curEv.tags {
									if case curTag.kind = nostr.Event.Tag.Kind.pubkey, let getPubKey = curTag.info.first {
										following.update(with:getPubKey)
									}
								}
								try self.relaysDB.setRelays(relays, pubkey:curEv.pubkey)
								try self.contactsDB.followDB.set(pubkey:curEv.pubkey, follows:following, tx:newTrans)
								self.logger.info("updated contact information for ")
							} catch {}
						default:
							self.logger.debug("got event.", metadata:["kind":"\(curEv.kind)"])
						}
					}
					let newEvsSet = Set(curEvs)
					try self.eventsDB.writeEvents(newEvsSet, tx:newTrans)
					try self.profilesDB.setPublicKeys(buildProfiles, tx:newTrans)
					try newTrans.commit()
				}
			}
			try newTrans.commit()
			self.logger.info("instance initialized.", metadata:["public_key":"\(keypair.pubkey)"])
		case let .failure(err):
			throw err
		}
	}

	func getHomeTimelineState() -> ([nostr.Event], [String:nostr.Profile]) {
		let readTX = try! Transaction(self.env, readOnly:true)
		let myEvents = try! self.eventsDB.getEvent(kind: .text_note, tx:readTX)
		let pubkeys = Set(myEvents.compactMap { $0.pubkey })
		let profiles = try! self.profilesDB.getPublicKeys(publicKeys:pubkeys, tx:readTX)
		try! readTX.commit()
		return (myEvents, profiles)
	}

	func buildMainUserFilters(tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Filter] {
		// get the friends list
		let myFriends = try self.contactsDB.followDB.getFollows(pubkey:self.keypair.pubkey, tx:someTrans)
		
		// build the contacts filter
		var contactsFilter = nostr.Filter()
		contactsFilter.authors = Array(myFriends)
		contactsFilter.kinds = [.metadata]

		// build the "our contacts" filter
		var ourContactsFilter = nostr.Filter()
		ourContactsFilter.kinds = [.metadata, .contacts]
		ourContactsFilter.authors = [self.keypair.pubkey]
		
		// build "blocklist" filter
		var blocklistFilter = nostr.Filter()
		blocklistFilter.kinds = [.list_categorized]
		blocklistFilter.parameter = ["mute"]
		blocklistFilter.authors = [self.keypair.pubkey]

		// build "dms" filter
		var dmsFilter = nostr.Filter()
		dmsFilter.kinds = [.dm]
		dmsFilter.authors = [self.keypair.pubkey]

		// build "our" dms filter
		var ourDMsFilter = nostr.Filter()
		ourDMsFilter.kinds = [.dm]
		ourDMsFilter.authors = [self.keypair.pubkey]

		// create home filter
		var homeFilter = nostr.Filter()
		homeFilter.kinds = [.text_note, .like, .boost]
		homeFilter.authors = Array(myFriends)

		// // create "notifications" filter
		// var notificationsFilter = nostr.Filter()
		// notificationsFilter.kinds = [.like, .boost, .text_note, .zap]
		// notificationsFilter.limit = 500

		// return [contactsFilter]
		return [contactsFilter, ourContactsFilter, blocklistFilter, dmsFilter, ourDMsFilter, homeFilter]
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
		
	}
}
