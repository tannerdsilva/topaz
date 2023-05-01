//
//  EventsEngine.swift
//  topaz
//
//  Created by Tanner Silva on 4/13/23.
//

import Foundation
import QuickLMDB
import struct CLMDB.MDB_dbi
import SwiftBlake2
import Logging
import AsyncAlgorithms


extension DBUX.EventsEngine.KindsEngine {
	struct Filter {
		let cursor:QuickLMDB.Cursor
		let kind:nostr.Event.Kind
		init(_ kind_keysig:Database, kind:nostr.Event.Kind, tx someTrans:QuickLMDB.Transaction) throws {
			let makeCursor = try kind_keysig.cursor(tx:someTrans)
			try makeCursor.getEntry(.set, key:kind)
			self.cursor = makeCursor
			self.kind = kind
		}
		
		func shouldInclude<D>(_ keysig:D) throws -> Bool where D:MDB_encodable {
			do {
				try cursor.getEntry(.getBoth, key:kind, value:keysig)
				return true
			} catch LMDBError.notFound {
				return false
			}
		}
	}
}

extension DBUX.EventsEngine {
	struct KindsEngine:SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		
		static let name = "event-engine-kind-id.mdb"
		static let deltaSize = size_t(5.12e+8)
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>

		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		
		enum Databases:String {
			case kind_uid = "kind-uid"
			case uid_kind = "uid-kind"
		}

		let logger:Logger

		// stores the given UIDs that are associated with the given kind
		let kind_uid:Database
		// stores the kind associated with the given UID
		let uid_kind:Database

		init(env:QuickLMDB.Environment, publicKey:nostr.Key, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = publicKey
			self.logger = try Topaz.makeDefaultLogger(label:"event-engine-kind-id.mdb")
			let someTrans = try Transaction(env, readOnly:false)
			self.kind_uid = try env.openDatabase(named:Databases.kind_uid.rawValue, flags:[.create, .dupSort], tx:someTrans)
			self.uid_kind = try env.openDatabase(named:Databases.uid_kind.rawValue, flags:[.create, .dupSort], tx:someTrans)
			try someTrans.commit()
		}

		/// bulk import events into the database
		/// - for each public key, the event kinds will attempt to be assigned
		/// - will NOT overwrite existing data if the specified public key is already in the database
		/// - will NOT throw ``LMDBError.keyExists`` if the public key is already in the database with the same kind
		func setEvent(_ events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent: someTrans)
			let uidKCursor = try self.uid_kind.cursor(tx:subTrans)
			let kUIDCursor = try self.kind_uid.cursor(tx:subTrans)
			for event in events {
				do {
					try uidKCursor.setEntry(value:event.kind, forKey:event.uid, flags:[.noOverwrite])
				} catch LMDBError.keyExists {}
				try kUIDCursor.setEntry(value:event.uid, forKey:event.kind)
			}
			try subTrans.commit()
			self.logger.debug("successfully installed events.", metadata:["count": "\(events.count)"])
		}

		/// get all kinds for a given uid
		/// - never throws LMDBError.notFound
		func getKinds(uids:Set<nostr.Event.UID>, tx someTrans:QuickLMDB.Transaction) throws -> [nostr.Event.UID:nostr.Event.Kind] {
			let uidKCursor = try self.uid_kind.cursor(tx:someTrans)
			var ret = [nostr.Event.UID:nostr.Event.Kind]()
			for uid in uids {
				ret[uid] = nostr.Event.Kind(try uidKCursor.getEntry(.set, key:uid).value)!
			}
			return ret
		}

		/// removes the given uids from the database
		func deleteEvents(uids:Set<nostr.Event.UID>, tx someTrans:QuickLMDB.Transaction) throws {
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
			self.logger.debug("successfully deleted events.", metadata:["count": "\(uids.count)"])
		}

		func getKindFilter(kind:nostr.Event.Kind, tx someTrans:QuickLMDB.Transaction) throws -> Filter {
			return try Filter(self.kind_uid, kind:kind, tx:someTrans)
		}
	}
}

extension DBUX {
	struct DatesEngine:SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		
		static let name = "event-engine-date-id.mdb"
		static let maxDBs:MDB_dbi = 2
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key
		let logger:Logger
		enum Databases:String {
			case date_uid = "date-uid"
			case uid_date = "uid-date"
		}

		// stores the given UIDs that are associated with the given date
		let date_uid:Database	// [DBUX.Date:nostr.Event.UID]
		// stores the date associated with the given UID
		let uid_date:Database	// [nostr.Event.UID:DBUX.Date]

		init(env:QuickLMDB.Environment, publicKey:nostr.Key, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = publicKey
			self.logger = Topaz.makeDefaultLogger(label:"event-engine-date-id.mdb")
			let someTrans = try Transaction(env, readOnly:false)
			self.date_uid = try env.openDatabase(named:Databases.date_uid.rawValue, flags:[.create, .dupSort], tx:someTrans)
			self.uid_date = try env.openDatabase(named:Databases.uid_date.rawValue, flags:[.create, .dupSort], tx:someTrans)
			try someTrans.commit()
		}

		func set(events:Set<nostr.Event>, tx someTrans:QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
			let dateUCursor = try self.date_uid.cursor(tx:subTrans)
			let uidDCursor = try self.uid_date.cursor(tx:subTrans)
			for event in events {
				try dateUCursor.setEntry(value:event.uid, forKey:event.created)
				try uidDCursor.setEntry(value:event.created, forKey:event.uid)
			}
			try subTrans.commit()
		}
	}
}

extension DBUX {
	struct PublishersEngine:SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		static let maxDBs: MDB_dbi = 2
		static let env_flags: QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<NotificationType>
		let env: QuickLMDB.Environment
		let pubkey: nostr.Key
		let logger: Logger
		enum Databases: String {
			case key_uid = "key-uid"
			case uid_key = "uid-key"
		}

		// stores the given UIDs that are associated with the given key
		let key_uid: Database // [nostr.Key: nostr.Event.UID]
		// stores the key associated with the given UID
		let uid_key: Database // [nostr.Event.UID: nostr.Key]

		init(env: QuickLMDB.Environment, publicKey: nostr.Key, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = publicKey
			self.logger = Topaz.makeDefaultLogger(label: "event-engine-key-uid.mdb")
			let someTrans = try Transaction(env, readOnly: false)
			self.key_uid = try env.openDatabase(named: Databases.key_uid.rawValue, flags: [.create, .dupSort], tx: someTrans)
			self.uid_key = try env.openDatabase(named: Databases.uid_key.rawValue, flags: [.create, .dupSort], tx: someTrans)
			try someTrans.commit()
		}

		func set(events: Set<nostr.Event>, tx someTrans: QuickLMDB.Transaction) throws {
			let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
			let keyUCursor = try self.key_uid.cursor(tx: subTrans)
			let uidKCursor = try self.uid_key.cursor(tx: subTrans)
			for event in events {
				try keyUCursor.setEntry(value: event.uid, forKey: event.pubkey)
				try uidKCursor.setEntry(value: event.pubkey, forKey: event.uid)
			}
			try subTrans.commit()
		}
	}
}


extension DBUX {
	struct EventsEngine:ExperienceEngine {
		typealias NotificationType = DBUX.Notification
		static let name = "events-engine.mdb"
		static let deltaSize = SizeMode.relativeGrowth(size_t(419430400))
		static let maxDBs:MDB_dbi = 32
		static let env_flags:QuickLMDB.Environment.Flags = [.noSubDir, .noSync]
		let dispatcher: Dispatcher<DBUX.Notification>
		var base:URL
		let env:QuickLMDB.Environment
		let pubkey:nostr.Key

		let logger:Logger
		let kindDB:KindsEngine
		let dateIDs:DatesEngine
		let publishers:PublishersEngine
		let timelineEngine:TimelineEngine
		let followsEngine:FollowsEngine
		let relaysEngine:RelaysEngine
		let profilesEngine:ProfilesEngine
		
		init(base: URL, env: QuickLMDB.Environment, publicKey: nostr.Key, dispatcher: Dispatcher<DBUX.Notification>) throws {
			self.base = base
			self.dispatcher = dispatcher
			self.kindDB = try Topaz.launchSharedExperienceEngine(KindsEngine.self, base:base, env:env, for: publicKey, dispatcher:dispatcher)
			self.dateIDs = try Topaz.launchSharedExperienceEngine(DatesEngine.self, base:base, env:env, for:publicKey, dispatcher: dispatcher)
			self.publishers = try Topaz.launchSharedExperienceEngine(PublishersEngine.self, base:base, env:env, for:publicKey, dispatcher: dispatcher)
			self.timelineEngine = try Topaz.launchSharedExperienceEngine(TimelineEngine.self, base:base, env:env, for:publicKey, dispatcher: dispatcher)
			self.followsEngine = try Topaz.launchSharedExperienceEngine(FollowsEngine.self, base: base, env:env, for:publicKey, dispatcher: dispatcher)
			self.relaysEngine = try Topaz.launchSharedExperienceEngine(RelaysEngine.self, base:base, env:env, for:publicKey, dispatcher:dispatcher)
			self.profilesEngine = try Topaz.launchSharedExperienceEngine(ProfilesEngine.self, base:base, env: env, for: publicKey, dispatcher: dispatcher)
			self.env = env
			self.pubkey = publicKey
			self.base = base
			self.logger = Topaz.makeDefaultLogger(label: "events-engine")
		}
	}
}

extension DBUX.EventsEngine {
	class TimelineEngine:SharedExperienceEngine {
		typealias NotificationType = DBUX.Notification
		static let deltaSize = size_t(5.12e+8)
		static let maxDBs: MDB_dbi = 1
		static let env_flags: QuickLMDB.Environment.Flags = [.noSubDir, .noReadAhead, .noSync]
		let dispatcher:Dispatcher<NotificationType>
		let env: QuickLMDB.Environment
		let pubkey: nostr.Key
		let logger: Logger
		enum Databases: String {
			case timelineMain_DB = "timelineMain_DB"
		}
		
		let decoder = JSONDecoder()
		let encoder = JSONEncoder()
		
		let allDB: Database // database structure [DBUX.DatedNostrEventUID: nostr.Event]

		required init(env: QuickLMDB.Environment, publicKey: nostr.Key, dispatcher:Dispatcher<NotificationType>) throws {
			self.dispatcher = dispatcher
			self.env = env
			self.pubkey = publicKey
			self.logger = Topaz.makeDefaultLogger(label: "timeline-engine.mdb")
			let someTrans = try Transaction(env, readOnly: false)
			self.allDB = try env.openDatabase(named:Databases.timelineMain_DB.rawValue, flags:[.create], tx: someTrans)
			try self.allDB.setCompare(tx:someTrans, DBUX.DatedNostrEventUID.mdbCompareFunction)
			let getEventsCount = try self.allDB.getStatistics(tx:someTrans).entries
			try someTrans.commit()
		}

		@discardableResult
		func writeEvents(_ events: Set<nostr.Event>, tx someTrans: QuickLMDB.Transaction) throws -> Set<DBUX.DatedNostrEventUID> {
//			let subTrans = Transaction(self.env, readOnly:false, parent:someTrans)
			let eventsByDateID = Dictionary(grouping: events, by: { DBUX.DatedNostrEventUID(event:$0) }).compactMapValues({ $0.first })
			let sortedDateIDs = eventsByDateID.keys.sorted(by: { $0 < $1 })
			var returnValues = Set<DBUX.DatedNostrEventUID>()

			let subTrans = try Transaction(env, readOnly: false, parent: someTrans)
			let allDBCursor = try self.allDB.cursor(tx: subTrans)
			for curDate in sortedDateIDs {
				let encoded = try encoder.encode(eventsByDateID[curDate]!)
				try allDBCursor.setEntry(value:encoded, forKey:curDate)
				returnValues.update(with:curDate)
			}
			try subTrans.commit()
			return returnValues
		}

		func readEvents(_ ids: Set<DBUX.DatedNostrEventUID>, tx someTrans: QuickLMDB.Transaction) throws -> [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>] {
			var returnValues = [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>]()
			let allDBCursor = try self.allDB.cursor(tx: someTrans)
			for curID in ids.sorted(by: { $0 < $1 }) {
				do {
					let curEvent = Data(try allDBCursor.getEntry(.set, key:curID).value)!
					returnValues[curID] = .success(try decoder.decode(nostr.Event.self, from:curEvent))
				} catch let error {
					returnValues[curID] = .failure(error)
				}
			}
			return returnValues
		}
		
		@discardableResult func deleteEvents(_ ids:Set<DBUX.DatedNostrEventUID>, tx someTrans:QuickLMDB.Transaction) throws -> [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>] {
			var returnValues = [DBUX.DatedNostrEventUID:Result<nostr.Event, Swift.Error>]()
			let allDBCursor = try self.allDB.cursor(tx: someTrans)
			for curID in ids.sorted(by: { $0 < $1 }) {
				do {
					let curEvent = Data(try allDBCursor.getEntry(.set, key:curID).value)!
					returnValues[curID] = .success(try decoder.decode(nostr.Event.self, from:curEvent))
					try allDBCursor.deleteEntry()
				} catch let error {
					returnValues[curID] = .failure(error)
				}
			}
			return returnValues
		}
		
		enum ReadDirection {
			case forward
			case backward
		}
		func readEvents(from marker: DBUX.DatedNostrEventUID?, limit: UInt16 = 48, direction: UI.TimelineViewModel.ScrollDirection, usersOut:inout Set<nostr.Key>, tx someTrans: QuickLMDB.Transaction, filter shouldInclude: (nostr.Event.UID) throws -> Bool) throws -> [nostr.Event] {
			let allDBCursor = try self.allDB.cursor(tx: someTrans)
			var returnValues: [nostr.Event] = []
			var currentEntry: (key: MDB_val, value: MDB_val)
			
			if let hasMarker = marker {
				do {
					currentEntry = try allDBCursor.getEntry(.set, key: hasMarker)
				} catch LMDBError.notFound {
					do {
						currentEntry = try allDBCursor.getEntry(.setRange, key: hasMarker)
					} catch LMDBError.notFound {
						currentEntry = try allDBCursor.getEntry(.last)
					}
				}
			} else {
				currentEntry = try allDBCursor.getEntry(.last)
			}
			
			do {
				repeat {
					let getUID = DBUX.DatedNostrEventUID(currentEntry.key)!.uid
					if try shouldInclude(getUID) == true {
						let parsed = try! decoder.decode(nostr.Event.self, from: Data(currentEntry.value)!)
						returnValues.append(parsed)
						usersOut.update(with:parsed.pubkey)
					}
					
					switch direction {
					case .up:
						currentEntry = try allDBCursor.getEntry(.next)
					case .down:
						currentEntry = try allDBCursor.getEntry(.previous)
					}
				} while returnValues.count < limit
			} catch LMDBError.notFound {
			}
			
			return returnValues
		}
	}

}
